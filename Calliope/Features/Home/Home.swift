//
//  Home.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import Foundation
import os

@Reducer
struct Home {
    @Reducer
    enum Destination {
        case alert(AlertState<Never>)
        case createEntry(EntryForm)
        case settings(Settings)
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
        var entries: IdentifiedArrayOf<Entry>?
        var isOnline = true
        var isSyncing = true
        var path = StackState<EntryDetail.State>()
        var searchText = ""
        let sessionOrigin: SessionOrigin
        var user: User

        @CasePathable
        enum SessionOrigin: Equatable {
            case freshSignIn(isNewAccount: Bool)
            case restored
        }

        init(user: User, sessionOrigin: SessionOrigin = .restored) {
            self.sessionOrigin = sessionOrigin
            self.user = user
        }

        var accountDeletionPhase: Settings.DeletionPhase? {
            guard case .settings(let settings)? = destination else { return nil }
            return settings.deletionPhase
        }

        var entryCount: Int { entries?.count ?? 0 }

        var filteredEntries: IdentifiedArrayOf<Entry> {
            guard let entries else { return [] }
            guard !searchText.isEmpty else { return entries }
            return entries.filter { entry in
                entry.term.localizedStandardContains(searchText)
                    || entry.definition.localizedStandardContains(searchText)
            }
        }

        var isFreshSignIn: Bool { sessionOrigin.is(\.freshSignIn) }

        var isLoadingFirstEntries: Bool { entries == nil }

        var syncStatus: SyncStatus {
            guard isOnline else { return .offline }
            return isSyncing ? .syncing : .synced
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case connectivityChanged(Bool)
        case destination(PresentationAction<Destination.Action>)
        case entriesRetryTimerElapsed
        case entriesStreamFailed
        case entriesUpdated(EntriesSnapshot)
        case entryDeleteFailed(Entry.ID, any Error)
        case entrySaveFailed(Entry.ID, any Error)
        case newEntryButtonTapped
        case path(StackActionOf<EntryDetail>)
        case settingsButtonTapped
        case task
    }

    enum CancelID {
        case connectivitySubscription
        case entriesSubscription
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.networkMonitorClient) var networkMonitorClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .connectivityChanged(let isOnline):
                state.isOnline = isOnline
                return .none

            case .destination(.presented(.createEntry(.delegate(.didSubmit(let entry))))):
                state.destination = nil
                return .merge(
                    .run { _ in await hapticsClient.success() },
                    save(entry, uid: state.user.uid)
                )

            case .destination:
                return .none

            case .entriesRetryTimerElapsed:
                return subscribeToEntries(state)

            case .entriesStreamFailed:
                state.isSyncing = true
                let retry: Effect<Action> =
                    .run { send in
                        try await clock.sleep(for: .seconds(5))
                        await send(.entriesRetryTimerElapsed)
                    }
                    .cancellable(id: CancelID.entriesSubscription, cancelInFlight: true)
                guard state.entries == nil else { return retry }
                state.entries = []
                return .merge(retry, celebrateFirstLoad(state))

            case .entriesUpdated(let snapshot):
                let isFirstLoad = state.entries == nil
                state.isSyncing = snapshot.isSyncing
                let entries = IdentifiedArray(uniqueElements: snapshot.entries)
                state.entries = entries
                for id in Array(state.path.ids) {
                    guard let entryID = state.path[id: id]?.entry.id else { continue }
                    if let entry = entries[id: entryID] {
                        state.path[id: id]?.entry = entry
                    } else {
                        state.path.pop(from: id)
                    }
                }
                guard isFirstLoad else { return .none }
                return celebrateFirstLoad(state)

            case .entryDeleteFailed(let id, let error):
                logger.error("Deleting entry \(id, privacy: .public) failed: \(error, privacy: .public)")
                guard state.destination == nil else { return .none }
                state.destination = .alert(.entryDeleteFailed)
                return .none

            case .entrySaveFailed(let id, let error):
                logger.error("Saving entry \(id, privacy: .public) failed: \(error, privacy: .public)")
                guard state.destination == nil else { return .none }
                state.destination = .alert(.entrySaveFailed)
                return .none

            case .newEntryButtonTapped:
                state.destination = .createEntry(EntryForm.State(mode: .create))
                return .none

            case .path(.element(id: let id, action: .delegate(.didDelete(let entryID)))):
                state.path.pop(from: id)
                return .merge(
                    .run { _ in await hapticsClient.warning() },
                    delete(entryID, uid: state.user.uid)
                )

            case .path(.element(id: _, action: .delegate(.didUpdate(let entry)))):
                return save(entry, uid: state.user.uid)

            case .path:
                return .none

            case .settingsButtonTapped:
                state.destination = .settings(Settings.State(user: state.user))
                return .none

            case .task:
                return .merge(
                    observeConnectivity(),
                    subscribeToEntries(state)
                )
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .forEach(\.path, action: \.path) {
            EntryDetail()
        }
    }

    private func celebrateFirstLoad(_ state: State) -> Effect<Action> {
        state.isFreshSignIn ? .run { _ in await hapticsClient.success() } : .none
    }

    private func delete(_ id: Entry.ID, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.delete(id: id, uid: uid)
        } catch: { error, send in
            await send(.entryDeleteFailed(id, error))
        }
    }

    private func observeConnectivity() -> Effect<Action> {
        .run { send in
            for await isOnline in networkMonitorClient.connectivityChanges() {
                await send(.connectivityChanged(isOnline))
            }
        }
        .cancellable(id: CancelID.connectivitySubscription, cancelInFlight: true)
    }

    private func save(_ entry: Entry, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.save(entry: entry, uid: uid)
        } catch: { error, send in
            await send(.entrySaveFailed(entry.id, error))
        }
    }

    private func subscribeToEntries(_ state: State) -> Effect<Action> {
        let uid = state.user.uid
        return
            .run { send in
                do {
                    let snapshots = await entriesClient.entries(uid: uid)
                    for try await snapshot in snapshots {
                        await send(.entriesUpdated(snapshot))
                    }
                } catch {
                    logger.error("Entries stream failed: \(error, privacy: .public)")
                    await send(.entriesStreamFailed)
                }
            }
            .cancellable(id: CancelID.entriesSubscription, cancelInFlight: true)
    }
}

extension Home.Destination.State: Equatable {}

extension AlertState where Action == Never {
    static let entryDeleteFailed = AlertState {
        TextState("Couldn't Delete Entry")
    } message: {
        TextState("Something went wrong while deleting your entry. Please try again.")
    }

    static let entrySaveFailed = AlertState {
        TextState("Couldn't Save Entry")
    } message: {
        TextState("Something went wrong while saving your entry. Please try again.")
    }
}

private let logger = Logger(category: "Home")
