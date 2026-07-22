//
//  SettingsView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 22/07/26.
//

import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    @Bindable var store: StoreOf<Settings>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Email") {
                        Text(store.user.email ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Sign Out") {
                        store.send(.signOutButtonTapped)
                    }
                    Button("Delete Account", role: .destructive) {
                        store.send(.deleteAccountButtonTapped)
                    }
                }
                .disabled(store.isDeletingAccount)
            }
            // A back button otherwise appears at this stack's root
            .navigationBarBackButtonHidden()
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .groupedBackground()
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .title) {
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.bold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss", systemImage: "xmark") {
                        store.send(.dismissButtonTapped)
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .disabled(store.isDeletingAccount)
                }
            }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
        .safeAreaInset(edge: .bottom) {
            Text("Version \(store.appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom)
        }
        .interactiveDismissDisabled(store.isDeletingAccount)
    }
}

#Preview {
    SettingsView(
        store: Store(initialState: Settings.State(user: .mock)) {
            Settings()
        }
    )
}
