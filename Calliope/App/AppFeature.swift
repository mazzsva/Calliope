//
//  AppFeature.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 26/07/26.
//

import ComposableArchitecture
import IssueReporting

@Reducer
struct AppFeature {
    @Reducer
    enum Scene {
        case home(Home)
        case signIn(SignIn)
    }

    @ObservableState
    struct State: Equatable {
        var accountDeletionPhase: AccountDeletionPhase?
        var isSignedOutSettling = false

        // Presented so a scene swap cancels the outgoing scene's effects
        @Presents var scene: Scene.State?

        enum AccountDeletionPhase: Equatable {
            case deleting
            case reauthenticating
        }

        var isDeletingAccount: Bool { accountDeletionPhase != nil }

        var isLoading: Bool {
            switch scene {
            case nil:
                return true
            case .home(let home):
                return isDeletingAccount || home.entries == nil
            case .signIn(let signIn):
                return isSignedOutSettling || signIn.isAuthenticating
            }
        }

        var loadingMessage: String? {
            switch scene {
            case .home where accountDeletionPhase == .deleting:
                return "Deleting your account…"
            case .home(let home) where home.entries == nil:
                // A fresh sign-in's overlay stays up until the first snapshot, so hold its message too
                guard case .freshSignIn(let isNewAccount) = home.sessionOrigin else { return nil }
                return Self.signInMessage(isCreatingAccount: isNewAccount)
            case .signIn(let signIn) where signIn.isSigningIn:
                return Self.signInMessage(isCreatingAccount: signIn.isCreatingAccount)
            case nil, .home, .signIn:
                return nil
            }
        }

        // Shared so the text never changes as the scene swaps from sign-in to home
        private static func signInMessage(isCreatingAccount: Bool) -> String {
            isCreatingAccount ? "Creating your account…" : "Signing in…"
        }
    }

    enum Action {
        case authResolutionTimedOut
        case authUserChanged(User?)
        case scene(PresentationAction<Scene.Action>)
        case signedOutSettleEnded
        case task
    }

    enum CancelID {
        case authResolutionTimeout
        case signedOutSettle
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .authResolutionTimedOut:
                guard state.scene == nil else { return .none }
                reportIssue("Auth state didn't resolve within 10 seconds; falling back to the sign-in screen.")
                state.scene = .signIn(SignIn.State())
                return .none

            case .authUserChanged(let user):
                return .merge(
                    .cancel(id: CancelID.authResolutionTimeout),
                    resolveAuthChange(&state, user: user)
                )

            case .scene(.presented(.home(.delegate(.accountDeletion(let event))))):
                switch event {
                case .confirmed:
                    state.accountDeletionPhase = .deleting
                case .ended:
                    state.accountDeletionPhase = nil
                case .started:
                    state.accountDeletionPhase = .reauthenticating
                }
                return .none

            case .scene:
                return .none

            case .signedOutSettleEnded:
                state.isSignedOutSettling = false
                return .none

            case .task:
                return .merge(
                    .run { send in
                        for await user in authClient.authStateChanges() {
                            await send(.authUserChanged(user))
                        }
                    },
                    .run { send in
                        // The auth listener should fire immediately; this catches a stall stranding the loading screen
                        try await clock.sleep(for: .seconds(10))
                        await send(.authResolutionTimedOut)
                    }
                    .cancellable(id: CancelID.authResolutionTimeout)
                )
            }
        }
        .ifLet(\.$scene, action: \.scene)
    }

    private func resolveAuthChange(_ state: inout State, user: User?) -> Effect<Action> {
        switch (state.scene, user) {
        case (nil, nil):
            state.scene = .signIn(SignIn.State())
            return .none

        case (nil, .some(let user)):
            state.scene = .home(Home.State(user: user))
            return .none

        case (.signIn(let signIn), .some(let user)):
            // A fresh sign-in was just authorized, so skip the redundant credential check
            let isFreshSignIn = signIn.isAuthenticating
            state.scene = .home(
                Home.State(
                    user: user,
                    sessionOrigin: isFreshSignIn
                        ? .freshSignIn(isNewAccount: signIn.isCreatingAccount)
                        : .restored
                )
            )
            return .none

        case (.signIn, nil):
            return .none

        case (.home(let home), .some(let user)) where home.user == user:
            return .none

        case (.home(let home), .some(let user)) where home.user.uid == user.uid:
            // Same account with updated profile fields, so home refreshes the user in place
            return .send(.scene(.presented(.home(.userChanged(user)))))

        case (.home, .some(let user)):
            // A different account appeared without an intermediate sign-out; home restarts itself as a fresh session
            state.accountDeletionPhase = nil
            return .send(.scene(.presented(.home(.userChanged(user)))))

        case (.home, nil):
            state.accountDeletionPhase = nil
            // Briefly hold the loading screen to smooth the transition back to sign-in
            state.isSignedOutSettling = true
            state.scene = .signIn(SignIn.State())
            return .merge(
                // Drop the signed-out user's cached entries so they can't linger on a shared device
                .run { _ in
                    try await entriesClient.clearLocalData()
                } catch: { error, _ in
                    reportIssue(error, "Clearing the local entries data after sign out failed.")
                },
                .run { send in
                    try await clock.sleep(for: .milliseconds(500))
                    await send(.signedOutSettleEnded)
                }
                .cancellable(id: CancelID.signedOutSettle, cancelInFlight: true)
            )
        }
    }
}

extension AppFeature.Scene.State: Equatable {}
