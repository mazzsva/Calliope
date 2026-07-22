//
//  Settings.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct Settings {
    enum Alert: Equatable {
        case confirmSignOut
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Settings.Alert>?
        let appVersion: String
        var user: User

        init(user: User) {
            @Dependency(\.appVersionClient) var appVersionClient
            appVersion = appVersionClient.appVersion()
            self.user = user
        }
    }

    enum Action {
        case alert(PresentationAction<Alert>)
        case dismissButtonTapped
        case signOutButtonTapped
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .alert(.presented(.confirmSignOut)):
                return .run { _ in
                    try await authClient.signOut()
                }

            case .alert:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

            case .signOutButtonTapped:
                state.alert = .confirmSignOut
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

extension AlertState where Action == Settings.Alert {
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
}
