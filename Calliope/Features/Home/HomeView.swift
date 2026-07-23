//
//  HomeView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    let store: StoreOf<Home>

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    LazyVStack(spacing: 16) {
                        ForEach(store.entries ?? []) { entry in
                            EntryCardView(entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .groupedBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .title) {
                    Text("Calliope")
                        .font(.title)
                        .fontWeight(.bold)
                }
            }
            .overlay {
                if store.entries?.isEmpty == true {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "tray.fill",
                        description: Text("Tap the plus button to add an entry.")
                    )
                }
            }
        }
        .task { await store.send(.task).finish() }
    }
}

#Preview("Populated") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        }
    )
}

#Preview("Empty") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        } withDependencies: {
            $0.entriesClient.entries = { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.empty)
                }
            }
        }
    )
}
