//
//  Home.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import Foundation
import IssueReporting

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
        @dynamicMemberLookup
        enum SessionOrigin: Equatable {
            case freshSignIn(isNewAccount: Bool)
            case restored
        }

        init(user: User, sessionOrigin: SessionOrigin = .restored) {
            self.sessionOrigin = sessionOrigin
            self.user = user
        }

        var filteredEntries: IdentifiedArrayOf<Entry> {
            guard let entries else { return [] }
            guard !searchText.isEmpty else { return entries }
            return entries.filter { entry in
                entry.term.localizedStandardContains(searchText)
                    || entry.definition.localizedStandardContains(searchText)
            }
        }

        var isFreshSignIn: Bool { sessionOrigin.is(\.freshSignIn) }

        var syncStatus: SyncStatus {
            guard isOnline else { return .offline }
            return isSyncing ? .syncing : .synced
        }
    }

    enum Action: BindableAction {
        case appBecameActive
        case binding(BindingAction<State>)
        case connectivityChanged(Bool)
        case delegate(Delegate)
        case destination(PresentationAction<Destination.Action>)
        case entriesResponse(EntriesSnapshot)
        case entriesRetryTimerElapsed
        case entriesStreamFailed
        case entryDeleteFailed(Entry.ID, any Error)
        case entrySaveFailed(Entry.ID, any Error)
        case firstLoadTimedOut
        case newEntryButtonTapped
        case path(StackActionOf<EntryDetail>)
        case settingsButtonTapped
        case task
        case userChanged(User)

        @CasePathable
        enum Delegate {
            case accountDeletion(AccountDeletionEvent)
        }
    }

    enum CancelID {
        case connectivitySubscription
        case entriesSubscription
        case firstLoadTimeout
    }

    @Dependency(\.appVersionClient) var appVersionClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.hapticsClient) var hapticsClient
    @Dependency(\.networkMonitorClient) var networkMonitorClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .appBecameActive:
                return subscribeToEntries(state)

            case .binding:
                return .none

            case .connectivityChanged(let isOnline):
                state.isOnline = isOnline
                return .none

            case .delegate:
                return .none

            case .destination(.presented(.createEntry(.delegate(.didSubmit(let entry))))):
                state.destination = nil
                return .merge(
                    .run { _ in await hapticsClient.success() },
                    save(entry, uid: state.user.uid)
                )

            case .destination(.presented(.settings(.delegate(.accountDeletion(let event))))):
                return .send(.delegate(.accountDeletion(event)))

            case .destination:
                return .none

            case .entriesResponse(let snapshot):
                let isFirstLoad = state.entries == nil
                if isFirstLoad, state.isFreshSignIn, snapshot.isFromCache, snapshot.entries.isEmpty {
                    return .none
                }
                state.isSyncing = snapshot.isFromCache || snapshot.hasPendingWrites
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
                return firstLoadEnded(state)

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
                return .merge(retry, firstLoadEnded(state))

            case .entryDeleteFailed(let id, let error):
                reportIssue(error, "Failed to delete entry \(id).")
                state.destination = .alert(.entryDeleteFailed)
                return .none

            case .entrySaveFailed(let id, let error):
                reportIssue(error, "Failed to save entry \(id).")
                state.destination = .alert(.entrySaveFailed)
                return .none

            case .firstLoadTimedOut:
                guard state.entries == nil else { return .none }
                reportIssue("First entries snapshot didn't arrive within 10 seconds; showing an empty list.")
                state.entries = []
                return firstLoadEnded(state)

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
                state.destination = .settings(
                    Settings.State(appVersion: appVersionClient.appVersion(), user: state.user)
                )
                return .none

            case .task:
                return .merge(
                    subscribeToEntries(state),
                    .run { send in
                        for await isOnline in networkMonitorClient.connectivityChanges() {
                            await send(.connectivityChanged(isOnline))
                        }
                    }
                    .cancellable(id: CancelID.connectivitySubscription, cancelInFlight: true)
                )

            case .userChanged(let user):
                guard user.uid == state.user.uid else {
                    state = State(user: user)
                    return subscribeToEntries(state)
                }
                state.user = user
                if state.destination.is(\.settings) {
                    state.destination?.modify(\.settings) { $0.user = user }
                }
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
        .forEach(\.path, action: \.path) {
            EntryDetail()
        }
    }

    private func delete(_ id: Entry.ID, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.delete(id: id, uid: uid)
        } catch: { error, send in
            await send(.entryDeleteFailed(id, error))
        }
    }

    private func firstLoadEnded(_ state: State) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.firstLoadTimeout),
            state.isFreshSignIn ? .run { _ in await hapticsClient.success() } : .none
        )
    }

    private func save(_ entry: Entry, uid: String) -> Effect<Action> {
        .run { _ in
            try await entriesClient.save(entry: entry, uid: uid)
        } catch: { error, send in
            await send(.entrySaveFailed(entry.id, error))
        }
    }

    private func subscribeToEntries(_ state: State) -> Effect<Action> {
        let isFirstLoad = state.entries == nil
        let uid = state.user.uid
        return .merge(
            .run { send in
                do {
                    for try await snapshot in entriesClient.entries(uid: uid) {
                        await send(.entriesResponse(snapshot))
                    }
                } catch {
                    reportIssue(error, "Entries stream failed.")
                    await send(.entriesStreamFailed)
                }
            }
            .cancellable(id: CancelID.entriesSubscription, cancelInFlight: true),
            isFirstLoad
                ? .run { send in
                    try await clock.sleep(for: .seconds(10))
                    await send(.firstLoadTimedOut)
                }
                .cancellable(id: CancelID.firstLoadTimeout, cancelInFlight: true)
                : .none
        )
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
