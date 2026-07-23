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

        var user: User

        init(user: User) {
            self.user = user
        }
    }

    enum Action {
        case entriesResponse(EntriesSnapshot)
        case entriesStreamFailed
        case firstLoadTimedOut
        case task
    }

    enum CancelID {
        case entriesSubscription
        case firstLoadTimeout
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .entriesResponse(let snapshot):
                let isFirstLoad = state.entries == nil
                state.entries = IdentifiedArray(uniqueElements: snapshot.entries)
                guard isFirstLoad else { return .none }
                return firstLoadEnded()

            case .entriesStreamFailed:
                guard state.entries == nil else { return .none }
                state.entries = []
                return firstLoadEnded()

            case .firstLoadTimedOut:
                guard state.entries == nil else { return .none }
                reportIssue("First entries snapshot didn't arrive within 10 seconds; showing an empty list.")
                state.entries = []
                return firstLoadEnded()

            case .task:
                return subscribeToEntries(state)
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
