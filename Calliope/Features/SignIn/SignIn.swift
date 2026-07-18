//
//  SignIn.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct SignIn {
    @ObservableState
    struct State: Equatable {
        var step: Step?

        enum Step: Equatable {
            case awaitingAuthorization
            case signingIn(isNewAccount: Bool)
        }

        var isAuthenticating: Bool { step != nil }

        var isCreatingAccount: Bool { step == .signingIn(isNewAccount: true) }

        // True once the user has authorized; the loading label waits for this so it never shows behind the Apple sheet
        var isSigningIn: Bool {
            if case .signingIn = step { return true }
            return false
        }
    }

    enum Action {
        case authorizationResponse(Result<AppleCredential, any Error>)
        case signInButtonTapped
        case signInResponse(Result<Void, any Error>)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .authorizationResponse(.success(let credential)):
                // Drives only the loading copy, so Apple's first-authorization heuristic is accurate enough
                state.step = .signingIn(isNewAccount: credential.isFirstAuthorization)
                return .run { send in
                    await send(.signInResponse(Result { try await authClient.signIn(credential: credential) }))
                }

            case .authorizationResponse(.failure):
                state.step = nil
                return .none

            case .signInButtonTapped:
                guard state.step == nil else { return .none }
                state.step = .awaitingAuthorization
                return .run { send in
                    await send(.authorizationResponse(Result { try await signInWithAppleClient.requestCredential() }))
                }

            // Keep the signing-in step until the auth listener swaps to the authenticated scene
            case .signInResponse(.success):
                return .none

            case .signInResponse(.failure):
                state.step = nil
                return .none
            }
        }
    }
}
