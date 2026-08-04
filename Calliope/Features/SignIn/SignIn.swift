//
//  SignIn.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import ComposableArchitecture
import Foundation
import os

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
    }

    enum Action {
        case alert(PresentationAction<Never>)
        case authorizationResponse(Result<AppleCredential, any Error>)
        case signInButtonTapped
        case signInFailed(any Error)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .alert:
                return .none

            case .authorizationResponse(.success(let credential)):
                state.step = .signingIn(isNewAccount: credential.isFirstAuthorization)
                return .run { _ in
                    try await authClient.signIn(credential: credential)
                } catch: { error, send in
                    await send(.signInFailed(error))
                }

            case .authorizationResponse(.failure(let error)):
                state.step = nil
                if !error.isSignInWithAppleCancellation {
                    logger.error("Apple authorization failed: \(error, privacy: .public)")
                    state.alert = .signInFailed
                }
                return .none

            case .signInButtonTapped:
                guard state.step == nil else { return .none }
                state.step = .awaitingAuthorization
                return .run { send in
                    await send(.authorizationResponse(Result { try await signInWithAppleClient.requestCredential() }))
                }

            case .signInFailed(let error):
                state.step = nil
                logger.error("Firebase sign-in failed: \(error, privacy: .public)")
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

private let logger = Logger(category: "SignIn")
