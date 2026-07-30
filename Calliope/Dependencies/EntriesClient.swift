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

    var entries: @Sendable (_ uid: String) -> AsyncThrowingStream<EntriesSnapshot, any Error> = { _ in
        AsyncThrowingStream { _ in }
    }

    var save: @Sendable (_ entry: Entry, _ uid: String) async throws -> Void
}

struct EntriesSnapshot: Equatable, Sendable {
    var entries: [Entry]
    var isFromCache: Bool
    var hasPendingWrites: Bool
}

extension EntriesSnapshot {
    static let empty = EntriesSnapshot(entries: [], isFromCache: false, hasPendingWrites: false)
    static let mock = EntriesSnapshot(entries: Entry.mocks, isFromCache: false, hasPendingWrites: false)
    static let syncing = EntriesSnapshot(entries: Entry.mocks, isFromCache: true, hasPendingWrites: false)
}

extension EntriesClient: DependencyKey {
    static var liveValue: EntriesClient {
        EntriesClient(
            clearLocalData: {
                let firestore = Firestore.firestore()
                try await firestore.terminate()
                try await firestore.clearPersistence()
            },
            delete: { id, uid in
                try await entriesCollection(uid: uid).document(id.uuidString).delete()
            },
            deleteAll: { uid in
                while true {
                    let snapshot = try await entriesCollection(uid: uid).limit(to: 500).getDocuments()
                    guard !snapshot.documents.isEmpty else { return }
                    let batch = Firestore.firestore().batch()
                    for document in snapshot.documents {
                        batch.deleteDocument(document.reference)
                    }
                    try await batch.commit()
                }
            },
            entries: { uid in
                AsyncThrowingStream { continuation in
                    let listener = entriesCollection(uid: uid)
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
                                    isFromCache: snapshot.metadata.isFromCache,
                                    hasPendingWrites: snapshot.metadata.hasPendingWrites
                                )
                            )
                        }
                    continuation.onTermination = { _ in
                        listener.remove()
                    }
                }
            },
            save: { entry, uid in
                try await entriesCollection(uid: uid).document(entry.id.uuidString).setData(entry.documentData)
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

private func entriesCollection(uid: String) -> CollectionReference {
    Firestore.firestore().collection("users").document(uid).collection("entries")
}

extension Entry {
    fileprivate init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard
            let id = UUID(uuidString: document.documentID),
            let term = data["term"] as? String,
            let definition = data["definition"] as? String,
            let isBookmarked = data["isBookmarked"] as? Bool,
            let createdAt = data["createdAt"] as? Timestamp,
            let updatedAt = data["updatedAt"] as? Timestamp
        else {
            reportIssue("Skipping entry document \(document.documentID) that failed to decode.")
            return nil
        }
        self.init(
            id: id,
            term: term,
            definition: definition,
            isBookmarked: isBookmarked,
            createdAt: createdAt.dateValue(),
            updatedAt: updatedAt.dateValue()
        )
    }

    fileprivate var documentData: [String: Any] {
        [
            "term": term,
            "definition": definition,
            "isBookmarked": isBookmarked,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
        ]
    }
}
