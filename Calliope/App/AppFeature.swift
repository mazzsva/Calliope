//
//  AppFeature.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 26/07/26.
//

import ComposableArchitecture
import IssueReporting
import os

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
                guard let isNewAccount = home.sessionOrigin.freshSignIn else { return nil }
                return Self.signInMessage(isCreatingAccount: isNewAccount)
            case .signIn(let signIn) where signIn.isSigningIn:
                return Self.signInMessage(isCreatingAccount: signIn.isCreatingAccount)
            case nil, .home, .signIn:
                return nil
            }
        }

        private static func signInMessage(isCreatingAccount: Bool) -> String {
            isCreatingAccount ? "Creating your account…" : "Signing in…"
        }
    }

    enum Action {
        case appBecameActive
        case appleCredentialRevoked
        case authResolutionTimedOut
        case authSessionEnded
        case authUserChanged(User?)
        case scene(PresentationAction<Scene.Action>)
        case signedOutSettleEnded
        case task
    }

    enum CancelID {
        case appleCredentialCheck
        case authObservation
        case authResolutionTimeout
        case signedOutSettle
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appBecameActive:
                guard state.scene.is(\.home), !state.isDeletingAccount else { return .none }
                return verifyAppleCredential()

            case .appleCredentialRevoked:
                guard state.scene.is(\.home), !state.isDeletingAccount else { return .none }
                logger.notice("Apple ID credential was revoked; signing out.")
                return .run { _ in
                    try await authClient.signOut()
                } catch: { error, _ in
                    logger.error("Sign out after Apple ID credential revocation failed: \(error, privacy: .public)")
                }

            case .authResolutionTimedOut:
                guard state.scene == nil else { return .none }
                reportIssue("Auth state didn't resolve within 10 seconds; falling back to the sign-in screen.")
                state.scene = .signIn(SignIn.State())
                return .none

            case .authSessionEnded:
                state.accountDeletionPhase = nil
                state.scene = nil
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
                    observeAuthChanges(),
                    .run { send in
                        for await _ in signInWithAppleClient.credentialRevocations() {
                            await send(.appleCredentialRevoked)
                        }
                    },
                    .run { send in
                        try await clock.sleep(for: .seconds(10))
                        await send(.authResolutionTimedOut)
                    }
                    .cancellable(id: CancelID.authResolutionTimeout)
                )
            }
        }
        .ifLet(\.$scene, action: \.scene)
    }

    private func observeAuthChanges() -> Effect<Action> {
        .run { send in
            var lastUID: String?
            for await user in authClient.authStateChanges() {
                if let user, let lastUID, lastUID != user.uid {
                    await send(.authSessionEnded)
                }
                lastUID = user?.uid
                await send(.authUserChanged(user))
            }
        }
        .cancellable(id: CancelID.authObservation, cancelInFlight: true)
    }

    private func resolveAuthChange(_ state: inout State, user: User?) -> Effect<Action> {
        switch (state.scene, user) {
        case (nil, nil):
            state.scene = .signIn(SignIn.State())
            return .none

        case (nil, .some(let user)):
            state.scene = .home(Home.State(user: user))
            return verifyAppleCredential()

        case (.signIn(let signIn), .some(let user)):
            let isFreshSignIn = signIn.isAuthenticating
            state.scene = .home(
                Home.State(
                    user: user,
                    sessionOrigin: isFreshSignIn
                        ? .freshSignIn(isNewAccount: signIn.isCreatingAccount)
                        : .restored
                )
            )
            return isFreshSignIn ? .none : verifyAppleCredential()

        case (.signIn, nil):
            return .none

        case (.home(let home), .some(let user)) where home.user == user:
            return .none

        case (.home(let home), .some(let user)) where home.user.uid == user.uid:
            return .send(.scene(.presented(.home(.userChanged(user)))))

        case (.home, .some):
            reportIssue("Auth changed accounts without signing out first; signing out.")
            return .run { _ in
                try await authClient.signOut()
            } catch: { error, _ in
                logger.error("Sign out after an unexpected account change failed: \(error, privacy: .public)")
            }

        case (.home, nil):
            state.accountDeletionPhase = nil
            state.isSignedOutSettling = true
            state.scene = .signIn(SignIn.State())
            return .merge(
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

    private func verifyAppleCredential() -> Effect<Action> {
        .run { _ in
            guard let appleUserID = authClient.appleUserID() else { return }
            switch await signInWithAppleClient.credentialState(forUserID: appleUserID) {
            case .authorized:
                return
            case .indeterminate, .notFound:
                logger.notice("Apple ID credential check found no definitive revocation; keeping the session.")
            case .revoked:
                logger.notice("Apple ID credential was revoked; signing out.")
                try await authClient.signOut()
            }
        } catch: { error, _ in
            logger.error("Sign out after Apple ID credential check failed: \(error, privacy: .public)")
        }
        .cancellable(id: CancelID.appleCredentialCheck, cancelInFlight: true)
    }
}

extension AppFeature.Scene.State: Equatable {}

private let logger = Logger(category: "AppFeature")
