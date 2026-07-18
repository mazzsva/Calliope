//
//  SignInView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 19/07/26.
//

import ComposableArchitecture
import SwiftUI

struct SignInView: View {
    let store: StoreOf<SignIn>

    var body: some View {
        VStack {
            Spacer()
            Text("Calliope")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            SignInWithAppleButton {
                store.send(.signInButtonTapped)
            }
            .disabled(store.isAuthenticating)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .groupedBackground()
    }
}

#Preview {
    SignInView(
        store: Store(initialState: SignIn.State()) {
            SignIn()
        }
    )
}
