//
//  SignIn.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import ComposableArchitecture
import Foundation
import IssueReporting
import os

@Reducer
struct SignIn {
    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Never>?
        var step: Step?

        @CasePathable
        enum Step: Equatable {
            case awaitingAuthorization
            case signingIn(isNewAccount: Bool)
        }

        var isAuthenticating: Bool { step != nil }

        var isCreatingAccount: Bool { step == .signingIn(isNewAccount: true) }

        var isSigningIn: Bool { step.is(\.signingIn) }
    }

    enum Action {
        case alert(PresentationAction<Never>)
        case authorizationResponse(Result<AppleCredential, any Error>)
        case signInButtonTapped
        case signInResponse(Result<Void, any Error>)
        case signInTransitionTimedOut
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .alert:
                return .none

            case .authorizationResponse(.success(let credential)):
                state.step = .signingIn(isNewAccount: credential.isFirstAuthorization)
                return .run { send in
                    await send(.signInResponse(Result { try await authClient.signIn(credential: credential) }))
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

            case .signInResponse(.success):
                return .run { send in
                    try await clock.sleep(for: .seconds(15))
                    await send(.signInTransitionTimedOut)
                }

            case .signInResponse(.failure(let error)):
                state.step = nil
                logger.error("Firebase sign-in failed: \(error, privacy: .public)")
                state.alert = .signInFailed
                return .none

            case .signInTransitionTimedOut:
                reportIssue("Firebase sign-in succeeded but the authenticated screen never appeared.")
                state.step = nil
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
