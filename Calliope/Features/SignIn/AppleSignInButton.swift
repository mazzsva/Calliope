//
//  AppleSignInButton.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import AuthenticationServices
import SwiftUI

struct AppleSignInButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppleSignInButtonRepresentable(action: action, style: colorScheme == .dark ? .white : .black)
            .clipShape(.capsule)
            .frame(height: 50)
            .id(colorScheme)
    }
}

private struct AppleSignInButtonRepresentable: UIViewRepresentable {
    let action: () -> Void
    let style: ASAuthorizationAppleIDButton.Style

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
    AppleSignInButton {}
        .padding(.horizontal, 32)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppleSignInButton {}
        .padding(.horizontal, 32)
        .preferredColorScheme(.dark)
}
