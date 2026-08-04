//
//  AppView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import ComposableArchitecture
import SwiftUI

struct AppView: View {
    let store: StoreOf<AppFeature>

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if let sceneStore = store.scope(state: \.scene, action: \.scene) {
                switch sceneStore.case {
                case .home(let homeStore):
                    HomeView(store: homeStore)
                case .signIn(let signInStore):
                    SignInView(store: signInStore)
                }
            } else {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
            }
        }
        .loadingWindow(isVisible: store.isLoading, message: store.loadingMessage)
        .task { await store.send(.task).finish() }
        .onChange(of: scenePhase) { _, newPhase in scenePhaseChanged(to: newPhase) }
    }

    private func scenePhaseChanged(to newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        store.send(.appBecameActive)
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
