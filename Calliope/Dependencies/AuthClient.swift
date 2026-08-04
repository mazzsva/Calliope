//
//  AuthClient.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import Dependencies
import DependenciesMacros
import FirebaseAuth

@DependencyClient
struct AuthClient: Sendable {
    var appleUserID: @Sendable () -> String? = { nil }
    var authStateChanges: @Sendable () -> AsyncStream<User?> = { AsyncStream { _ in } }
    var deleteAccount: @Sendable () async throws -> Void
    var reauthenticate: @Sendable (_ credential: AppleCredential) async throws -> Void
    var revokeAppleToken: @Sendable (_ authorizationCode: String) async throws -> Void
    var signIn: @Sendable (_ credential: AppleCredential) async throws -> Void
    var signOut: @Sendable () async throws -> Void
}

extension AuthClient: DependencyKey {
    static var liveValue: AuthClient {
        AuthClient(
            appleUserID: {
                Auth.auth().currentUser?.providerData
                    .first { $0.providerID == AuthProviderID.apple.rawValue }?
                    .uid
            },
            authStateChanges: {
                AsyncStream { continuation in
                    nonisolated(unsafe) let handle = Auth.auth()
                        .addStateDidChangeListener { _, user in
                            continuation.yield(user.map { User(email: $0.email, uid: $0.uid) })
                        }
                    continuation.onTermination = { _ in
                        Auth.auth().removeStateDidChangeListener(handle)
                    }
                }
            },
            deleteAccount: {
                try await currentUser().delete()
            },
            reauthenticate: { credential in
                try await currentUser().reauthenticate(with: firebaseCredential(from: credential))
            },
            revokeAppleToken: { authorizationCode in
                try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
            },
            signIn: { credential in
                try await Auth.auth().signIn(with: firebaseCredential(from: credential))
            },
            signOut: {
                try Auth.auth().signOut()
            }
        )
    }

    static var previewValue: AuthClient {
        AuthClient(
            appleUserID: { "mock-apple-user-id" },
            authStateChanges: {
                AsyncStream { continuation in
                    continuation.yield(.mock)
                }
            },
            deleteAccount: {},
            reauthenticate: { _ in },
            revokeAppleToken: { _ in },
            signIn: { _ in },
            signOut: {}
        )
    }

    static var testValue: AuthClient {
        AuthClient()
    }
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

private enum AuthClientError: Error {
    case notSignedIn
}

private func currentUser() throws -> FirebaseAuth.User {
    guard let user = Auth.auth().currentUser else { throw AuthClientError.notSignedIn }
    return user
}

private func firebaseCredential(from credential: AppleCredential) -> AuthCredential {
    OAuthProvider.appleCredential(
        withIDToken: credential.idToken,
        rawNonce: credential.rawNonce,
        fullName: nil
    )
}
