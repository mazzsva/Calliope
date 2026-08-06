//
//  SyncStatusLabel.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import SwiftUI

enum SyncStatus: Equatable {
    case offline
    case synced
    case syncing
}

struct SyncStatusLabel: View {
    let entryCount: Int
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 5) {
            if status == .syncing {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .animation(.default, value: status)
    }

    private var text: LocalizedStringKey {
        switch status {
        case .offline:
            "No Internet"
        case .synced, .syncing:
            entryCount == 0 ? "No Entries" : "^[\(entryCount) Entry](inflect: true)"
        }
    }
}

#Preview("In Toolbar") {
    NavigationStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .title) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Calliope")
                            .font(.title)
                            .fontWeight(.bold)
                        SyncStatusLabel(entryCount: 24, status: .syncing)
                    }
                }
            }
    }
}

#Preview("States") {
    VStack(alignment: .leading, spacing: 16) {
        SyncStatusLabel(entryCount: 24, status: .synced)
        SyncStatusLabel(entryCount: 1, status: .synced)
        SyncStatusLabel(entryCount: 0, status: .synced)
        SyncStatusLabel(entryCount: 24, status: .syncing)
        SyncStatusLabel(entryCount: 24, status: .offline)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .groupedBackground()
}
