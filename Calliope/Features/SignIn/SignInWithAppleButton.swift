//
//  SignInWithAppleButton.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import AuthenticationServices
import SwiftUI

// Apple's UIKit sign-in button wrapped for a plain tap action, since SwiftUI's bundles the authorization flow
struct SignInWithAppleButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The button's style is fixed at init, so rebuild it when the color scheme flips
        SignInWithAppleButtonRepresentable(style: colorScheme == .dark ? .white : .black, action: action)
            .clipShape(.capsule)
            .frame(height: 50)
            .id(colorScheme)
    }
}

private struct SignInWithAppleButtonRepresentable: UIViewRepresentable {
    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: style
        )
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        button.isEnabled = isEnabled
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonTapped() {
            action()
        }
    }
}

#Preview("Light") {
    SignInWithAppleButton {}
        .padding(.horizontal, 32)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SignInWithAppleButton {}
        .padding(.horizontal, 32)
        .preferredColorScheme(.dark)
}
