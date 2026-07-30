//
//  Settings.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import ComposableArchitecture
import Foundation
import IssueReporting

@Reducer
struct Settings {
    enum Alert: Equatable {
        case confirmAccountDeletion
        case confirmSignOut
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Settings.Alert>?
        let appVersion: String
        var hasDeletedEntries = false
        var isDeletingAccount = false
        var user: User

        init(user: User) {
            @Dependency(\.appVersionClient) var appVersionClient
            appVersion = appVersionClient.appVersion()
            self.user = user
        }
    }

    enum Action {
        case accountDeletionFailed(any Error)
        case alert(PresentationAction<Alert>)
        case delegate(Delegate)
        case deleteAccountButtonTapped
        case dismissButtonTapped
        case entriesDeleted
        case signOutButtonTapped
        case signOutFailed(any Error)

        @CasePathable
        enum Delegate {
            case accountDeletion(AccountDeletionEvent)
        }
    }

    enum AccountDeletionError: Error {
        case missingAuthorizationCode
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.entriesClient) var entriesClient
    @Dependency(\.signInWithAppleClient) var signInWithAppleClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .accountDeletionFailed(let error):
                state.isDeletingAccount = false
                if !error.isSignInWithAppleCancellation {
                    reportIssue(error, "Account deletion failed.")
                    state.alert = state.hasDeletedEntries ? .accountDeletionIncomplete : .accountDeletionFailed
                }
                return .send(.delegate(.accountDeletion(.ended)))

            case .alert(.presented(.confirmAccountDeletion)):
                state.isDeletingAccount = true
                let uid = state.user.uid
                return .merge(
                    .send(.delegate(.accountDeletion(.started))),
                    .run { send in
                        do {
                            let credential = try await signInWithAppleClient.requestCredential()
                            guard let authorizationCode = credential.authorizationCode else {
                                throw AccountDeletionError.missingAuthorizationCode
                            }
                            await send(.delegate(.accountDeletion(.confirmed)))
                            try await authClient.reauthenticate(credential: credential)
                            try await entriesClient.deleteAll(uid: uid)
                            await send(.entriesDeleted)
                            try await authClient.revokeAppleToken(authorizationCode: authorizationCode)
                            try await authClient.deleteAccount()
                        } catch {
                            await send(.accountDeletionFailed(error))
                        }
                    }
                )

            case .alert(.presented(.confirmSignOut)):
                return .run { _ in
                    try await authClient.signOut()
                } catch: { error, send in
                    await send(.signOutFailed(error))
                }

            case .alert:
                return .none

            case .delegate:
                return .none

            case .deleteAccountButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                state.alert = .confirmAccountDeletion
                return .none

            case .dismissButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                return .run { _ in await dismiss() }

            case .entriesDeleted:
                state.hasDeletedEntries = true
                return .none

            case .signOutButtonTapped:
                guard !state.isDeletingAccount else { return .none }
                state.alert = .confirmSignOut
                return .none

            case .signOutFailed(let error):
                reportIssue(error, "Sign out failed.")
                state.alert = .signOutFailed
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

extension AlertState where Action == Settings.Alert {
    static let accountDeletionFailed = AlertState {
        TextState("Couldn't Delete Account")
    } message: {
        TextState("Something went wrong while deleting your account. Please try again.")
    }

    static let accountDeletionIncomplete = AlertState {
        TextState("Account Not Deleted")
    } message: {
        TextState(
            "Your entries were deleted, but the account was not. Please try again to finish deleting your account."
        )
    }

    static let confirmAccountDeletion = AlertState {
        TextState("Delete Account")
    } actions: {
        ButtonState(role: .destructive, action: .confirmAccountDeletion) {
            TextState("Delete")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Are you sure you want to delete your account?")
    }

    static let confirmSignOut = AlertState {
        TextState("Sign Out")
    } actions: {
        ButtonState(role: .destructive, action: .confirmSignOut) {
            TextState("Sign Out")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Are you sure you want to sign out?")
    }

    static let signOutFailed = AlertState {
        TextState("Couldn't Sign Out")
    } message: {
        TextState("Something went wrong while signing out. Please try again.")
    }
}
