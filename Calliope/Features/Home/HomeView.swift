//
//  HomeView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<Home>

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    LazyVStack(spacing: 16) {
                        ForEach(store.filteredEntries) { entry in
                            EntryCardView(entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .groupedBackground()
            .searchable(text: $store.searchText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .title) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Calliope")
                            .font(.title)
                            .fontWeight(.bold)
                        SyncStatusLabel(status: store.syncStatus, entryCount: store.entries?.count ?? 0)
                    }
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .overlay {
                if store.entries?.isEmpty == true {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "tray.fill",
                        description: Text("Tap the plus button to add an entry.")
                    )
                } else if store.entries != nil, store.filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
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

#Preview("Syncing") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        } withDependencies: {
            $0.entriesClient.entries = { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.syncing)
                }
            }
        }
    )
}

#Preview("Offline") {
    HomeView(
        store: Store(initialState: Home.State(user: .mock)) {
            Home()
        } withDependencies: {
            $0.networkMonitorClient.connectivityChanges = {
                AsyncStream { continuation in
                    continuation.yield(false)
                }
            }
        }
    )
}
