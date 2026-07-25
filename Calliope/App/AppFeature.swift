//
//  AppFeature.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 26/07/26.
//

import ComposableArchitecture

@Reducer
struct AppFeature {
    @Reducer
    enum Scene {
        case home(Home)
        case signIn(SignIn)
    }

    @ObservableState
    struct State: Equatable {
        // Presented so a scene swap cancels the outgoing scene's effects
        @Presents var scene: Scene.State?

        var isLoading: Bool {
            switch scene {
            case nil:
                return true
            case .home(let home):
                return home.entries == nil
            case .signIn(let signIn):
                return signIn.isAuthenticating
            }
        }

        var loadingMessage: String? {
            switch scene {
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
        case authUserChanged(User?)
        case scene(PresentationAction<Scene.Action>)
        case task
    }

    @Dependency(\.authClient) var authClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .authUserChanged(let user):
                return resolveAuthChange(&state, user: user)

            case .scene:
                return .none

            case .task:
                return .run { send in
                    for await user in authClient.authStateChanges() {
                        await send(.authUserChanged(user))
                    }
                }
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
            return .send(.scene(.presented(.home(.userChanged(user)))))

        case (.home, nil):
            state.scene = .signIn(SignIn.State())
            return .none
        }
    }
}

extension AppFeature.Scene.State: Equatable {}
