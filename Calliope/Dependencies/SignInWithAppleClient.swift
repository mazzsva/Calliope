//
//  SignInWithAppleClient.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import AuthenticationServices
import CryptoKit
import Dependencies
import DependenciesMacros
import Foundation
import Security
import UIKit

@DependencyClient
struct SignInWithAppleClient: Sendable {
    var requestCredential: @Sendable () async throws -> AppleCredential
}

struct AppleCredential: Equatable, Sendable {
    var authorizationCode: String?
    var idToken: String
    var isFirstAuthorization: Bool
    var rawNonce: String
}

extension AppleCredential {
    static let mock = AppleCredential(
        authorizationCode: "mock-authorization-code",
        idToken: "mock-id-token",
        isFirstAuthorization: false,
        rawNonce: "mock-raw-nonce"
    )
}

extension SignInWithAppleClient: DependencyKey {
    static var liveValue: SignInWithAppleClient {
        SignInWithAppleClient(
            requestCredential: {
                // Apple signs a hash of the nonce; Firebase verifies it against the raw value
                let rawNonce = randomNonce()
                let authorization = try await performAuthorization(hashedNonce: sha256(rawNonce))
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    throw ASAuthorizationError(.invalidResponse)
                }
                return AppleCredential(
                    authorizationCode: credential.authorizationCode
                        .flatMap { String(data: $0, encoding: .utf8) },
                    idToken: idToken,
                    // Apple only returns the email on the very first authorization
                    isFirstAuthorization: credential.email != nil,
                    rawNonce: rawNonce
                )
            }
        )
    }

    static var previewValue: SignInWithAppleClient {
        SignInWithAppleClient(
            requestCredential: { .mock }
        )
    }

    static var testValue: SignInWithAppleClient {
        SignInWithAppleClient()
    }
}

extension DependencyValues {
    var signInWithAppleClient: SignInWithAppleClient {
        get { self[SignInWithAppleClient.self] }
        set { self[SignInWithAppleClient.self] = newValue }
    }
}

extension Error {
    var isSignInWithAppleCancellation: Bool {
        (self as? ASAuthorizationError)?.code == .canceled
    }
}

private func randomNonce(byteCount: Int = 32) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "Unable to generate a random nonce.")
    return bytes.map { String(format: "%02x", $0) }.joined()
}

private func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}

@MainActor
private func performAuthorization(hashedNonce: String) async throws -> ASAuthorization {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.email]
    request.nonce = hashedNonce
    return try await AuthorizationCoordinator().perform(request)
}

@MainActor
private final class AuthorizationCoordinator: NSObject {
    private var continuation: CheckedContinuation<ASAuthorization, any Error>?
    private var controller: ASAuthorizationController?

    func perform(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            // Hold the controller so it isn't deallocated before its delegate callbacks fire
            self.controller = controller
            controller.performRequests()
        }
    }

    private func resume(with result: Result<ASAuthorization, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

extension AuthorizationCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            resume(with: .success(authorization))
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        Task { @MainActor in
            resume(with: .failure(error))
        }
    }
}

extension AuthorizationCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // The system delivers this callback on the main thread despite the nonisolated signature
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            guard let anchor = windows.first(where: \.isKeyWindow) ?? windows.first else {
                preconditionFailure("No window available to present Sign in with Apple.")
            }
            return anchor
        }
    }
}
