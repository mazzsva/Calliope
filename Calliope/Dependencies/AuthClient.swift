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
    var authStateChanges: @Sendable () -> AsyncStream<User?> = { AsyncStream { _ in } }
    var signIn: @Sendable (_ credential: AppleCredential) async throws -> Void
    var signOut: @Sendable () async throws -> Void
}

extension AuthClient: DependencyKey {
    static var liveValue: AuthClient {
        AuthClient(
            authStateChanges: {
                AsyncStream { continuation in
                    let handle = Auth.auth()
                        .addStateDidChangeListener { _, user in
                            continuation.yield(user.map { User(uid: $0.uid, email: $0.email) })
                        }
                    continuation.onTermination = { _ in
                        Auth.auth().removeStateDidChangeListener(handle)
                    }
                }
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
            authStateChanges: {
                AsyncStream { continuation in
                    continuation.yield(.mock)
                }
            },
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

private func firebaseCredential(from credential: AppleCredential) -> AuthCredential {
    OAuthProvider.appleCredential(
        withIDToken: credential.idToken,
        rawNonce: credential.rawNonce,
        fullName: nil
    )
}
