//
//  SignIn.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import ComposableArchitecture
import Foundation
import IssueReporting

@Reducer
struct SignIn {
    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Never>?
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
        case alert(PresentationAction<Never>)
        case authorizationResponse(Result<AppleCredential, any Error>)
        case signInButtonTapped
        case signInResponse(Result<Void, any Error>)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .alert:
                return .none

            case .authorizationResponse(.success(let credential)):
                // Drives only the loading copy, so Apple's first-authorization heuristic is accurate enough
                state.step = .signingIn(isNewAccount: credential.isFirstAuthorization)
                return .run { send in
                    await send(.signInResponse(Result { try await authClient.signIn(credential: credential) }))
                }

            case .authorizationResponse(.failure(let error)):
                state.step = nil
                if !error.isSignInWithAppleCancellation {
                    reportIssue(error, "Sign in failed.")
                    state.alert = .signInFailed
                }
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

            case .signInResponse(.failure(let error)):
                // A cancellation can't reach here; the Apple sheet is already dismissed, so any failure is real
                state.step = nil
                reportIssue(error, "Sign in failed.")
                state.alert = .signInFailed
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

extension AlertState where Action == Never {
    static let signInFailed = AlertState {
        TextState("Couldn't Sign In")
    } message: {
        TextState("Something went wrong while signing in. Please try again.")
    }
}
