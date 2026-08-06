//
//  EntryFormView.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 20/07/26.
//

import ComposableArchitecture
import SwiftUI

struct EntryFormView: View {
    @Bindable var store: StoreOf<EntryForm>

    @FocusState private var isTermFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Term") {
                    TextField("", text: $store.term)
                        .focused($isTermFocused)
                }
                Section("Definition") {
                    TextEditor(text: $store.definition)
                        .frame(minHeight: 180)
                }
            }
            .scrollContentBackground(.hidden)
            .groupedBackground()
            .navigationTitle(store.isCreating ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        store.send(.saveButtonTapped)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!store.isSubmittable)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") {
                        store.send(.dismissButtonTapped)
                    }
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                }
            }
            .onAppear { focusTermForNewEntry() }
        }
    }

    private func focusTermForNewEntry() {
        guard store.isCreating else { return }
        isTermFocused = true
    }
}

#Preview("Create") {
    EntryFormView(
        store: Store(initialState: EntryForm.State()) {
            EntryForm()
        }
    )
}

#Preview("Edit") {
    EntryFormView(
        store: Store(initialState: EntryForm.State(entry: .mock)) {
            EntryForm()
        }
    )
}
