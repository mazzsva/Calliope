//
//  EntriesClient.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import Dependencies
import DependenciesMacros
import FirebaseFirestore
import Foundation
import IssueReporting

@DependencyClient
struct EntriesClient: Sendable {
    var clearLocalData: @Sendable () async throws -> Void
    var delete: @Sendable (_ id: Entry.ID, _ uid: String) async throws -> Void
    var deleteAll: @Sendable (_ uid: String) async throws -> Void

    var entries: @Sendable (_ uid: String) async -> AsyncThrowingStream<EntriesSnapshot, any Error> = { _ in
        AsyncThrowingStream { _ in }
    }

    var save: @Sendable (_ entry: Entry, _ uid: String) async throws -> Void
}

struct EntriesSnapshot: Equatable, Sendable {
    var entries: [Entry]
    var isSyncing: Bool
}

extension EntriesSnapshot {
    static let empty = EntriesSnapshot(entries: [], isSyncing: false)
    static let mock = EntriesSnapshot(entries: Entry.mocks, isSyncing: false)
    static let syncing = EntriesSnapshot(entries: Entry.mocks, isSyncing: true)
}

extension EntriesClient: DependencyKey {
    static var liveValue: EntriesClient {
        EntriesClient(
            clearLocalData: {
                try await FirestoreStorage.shared.clearLocalData()
            },
            delete: { id, uid in
                try await FirestoreStorage.shared.delete(id: id, uid: uid)
            },
            deleteAll: { uid in
                try await FirestoreStorage.shared.deleteAll(uid: uid)
            },
            entries: { uid in
                await FirestoreStorage.shared.entries(uid: uid)
            },
            save: { entry, uid in
                try await FirestoreStorage.shared.save(entry, uid: uid)
            }
        )
    }

    static var previewValue: EntriesClient {
        EntriesClient(
            clearLocalData: {},
            delete: { _, _ in },
            deleteAll: { _ in },
            entries: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.mock)
                }
            },
            save: { _, _ in }
        )
    }

    static var testValue: EntriesClient {
        EntriesClient()
    }
}

extension DependencyValues {
    var entriesClient: EntriesClient {
        get { self[EntriesClient.self] }
        set { self[EntriesClient.self] = newValue }
    }
}

private actor FirestoreStorage {
    static let shared = FirestoreStorage()

    private var clearing: Task<Void, any Error>?

    func clearLocalData() async throws {
        if let clearing {
            return try await clearing.value
        }
        let clearing = Task {
            let firestore = Firestore.firestore()
            try await firestore.terminate()
            try await firestore.clearPersistence()
        }
        self.clearing = clearing
        defer { self.clearing = nil }
        try await clearing.value
    }

    func delete(id: Entry.ID, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(id.uuidString).delete()
    }

    func deleteAll(uid: String) async throws {
        await waitForClearing()
        while true {
            try Task.checkCancellation()
            let snapshot = try await entriesCollection(uid: uid).limit(to: 500).getDocuments()
            guard !snapshot.documents.isEmpty else { return }
            let batch = Firestore.firestore().batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }
    }

    func entries(uid: String) async -> AsyncThrowingStream<EntriesSnapshot, any Error> {
        await waitForClearing()
        return AsyncThrowingStream { continuation in
            nonisolated(unsafe) let listener = entriesCollection(uid: uid)
                .order(by: "createdAt", descending: true)
                .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let snapshot else { return }
                    continuation.yield(
                        EntriesSnapshot(
                            entries: snapshot.documents.compactMap(Entry.init(document:)),
                            isSyncing: snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites
                        )
                    )
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func save(_ entry: Entry, uid: String) async throws {
        await waitForClearing()
        try await entriesCollection(uid: uid).document(entry.id.uuidString).setData(entry.documentData)
    }

    private func waitForClearing() async {
        _ = try? await clearing?.value
    }
}

private func entriesCollection(uid: String) -> CollectionReference {
    Firestore.firestore().collection("users").document(uid).collection("entries")
}

extension Entry {
    fileprivate init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let createdAt = data["createdAt"] as? Timestamp,
            let definition = data["definition"] as? String,
            let id = UUID(uuidString: document.documentID),
            let isBookmarked = data["isBookmarked"] as? Bool,
            let term = data["term"] as? String,
            let updatedAt = data["updatedAt"] as? Timestamp
        else {
            reportIssue("Skipping entry document \(document.documentID) that failed to decode.")
            return nil
        }
        self.init(
            createdAt: createdAt.dateValue(),
            definition: definition,
            id: id,
            isBookmarked: isBookmarked,
            term: term,
            updatedAt: updatedAt.dateValue()
        )
    }

    fileprivate var documentData: [String: Any] {
        [
            "createdAt": Timestamp(date: createdAt),
            "definition": definition,
            "isBookmarked": isBookmarked,
            "term": term,
            "updatedAt": Timestamp(date: updatedAt),
        ]
    }
}
