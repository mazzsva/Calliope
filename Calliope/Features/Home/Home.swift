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
    @ObservableState
    struct State: Equatable {
        // Nil until the first load settles, letting the UI tell loading from empty
        var entries: IdentifiedArrayOf<Entry>?

        var isOnline = true

        // Assume syncing until a server-confirmed snapshot arrives
        var isSyncing = true

        var searchText = ""

        var user: User

        init(user: User) {
            self.user = user
        }

        var syncStatus: SyncStatus {
            guard isOnline else { return .offline }
            return isSyncing ? .syncing : .synced
        }

        var filteredEntries: IdentifiedArrayOf<Entry> {
            guard let entries else { return [] }
            guard !searchText.isEmpty else { return entries }
            return entries.filter { entry in
                entry.term.localizedStandardContains(searchText)
                    || entry.definition.localizedStandardContains(searchText)
            }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case connectivityChanged(Bool)
        case entriesResponse(EntriesSnapshot)
        case entriesRetryTimerElapsed
        case entriesStreamFailed
        case firstLoadTimedOut
        case task
    }

    enum CancelID {
        case connectivitySubscription
        case entriesSubscription
        case firstLoadTimeout
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient
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

            case .entriesResponse(let snapshot):
                let isFirstLoad = state.entries == nil
                state.isSyncing = snapshot.isFromCache || snapshot.hasPendingWrites
                state.entries = IdentifiedArray(uniqueElements: snapshot.entries)
                guard isFirstLoad else { return .none }
                return firstLoadEnded()

            case .entriesRetryTimerElapsed:
                return subscribeToEntries(state)

            case .entriesStreamFailed:
                // Firestore won't revive a failed listener, so surface the stall and retry after a pause
                state.isSyncing = true
                let retry: Effect<Action> =
                    .run { send in
                        try await clock.sleep(for: .seconds(5))
                        await send(.entriesRetryTimerElapsed)
                    }
                    // Reuses the subscription's id so a restart from foregrounding supersedes a pending retry
                    .cancellable(id: CancelID.entriesSubscription, cancelInFlight: true)
                guard state.entries == nil else { return retry }
                state.entries = []
                return .merge(retry, firstLoadEnded())

            case .firstLoadTimedOut:
                guard state.entries == nil else { return .none }
                reportIssue("First entries snapshot didn't arrive within 10 seconds; showing an empty list.")
                state.entries = []
                return firstLoadEnded()

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
            }
        }
    }

    private func firstLoadEnded() -> Effect<Action> {
        .cancel(id: CancelID.firstLoadTimeout)
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
