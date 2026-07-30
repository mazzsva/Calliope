//
//  EntryDetailView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import SwiftUI

struct EntryDetailView: View {
    @Bindable var store: StoreOf<EntryDetail>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.entry.term)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(store.entry.definition)

                Text("Created \(store.entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    store.send(.editButtonTapped)
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.bookmarkButtonTapped)
                } label: {
                    Image(systemName: store.entry.isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .tint(store.entry.isBookmarked ? .bookmark : .secondary)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete Entry", role: .destructive) {
                    store.send(.deleteButtonTapped)
                }
                .tint(.red)
            }
        }
        .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
        .sheet(
            item: $store.scope(state: \.destination?.editEntry, action: \.destination.editEntry)
        ) { formStore in
            EntryFormView(store: formStore)
        }
    }
}

#Preview("Bookmarked") {
    NavigationStack {
        EntryDetailView(
            store: Store(initialState: EntryDetail.State(entry: .mock)) {
                EntryDetail()
            }
        )
    }
}

#Preview("Not Bookmarked") {
    NavigationStack {
        EntryDetailView(
            store: Store(initialState: EntryDetail.State(entry: .unbookmarkedMock)) {
                EntryDetail()
            }
        )
    }
}
