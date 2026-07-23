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
    let status: SyncStatus
    let entryCount: Int

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

    private var text: String {
        switch status {
        case .offline:
            "No Internet"
        case .synced, .syncing:
            countText
        }
    }

    private var countText: String {
        switch entryCount {
        case 0:
            "No Entries"
        case 1:
            "1 Entry"
        default:
            "\(entryCount) Entries"
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
                        SyncStatusLabel(status: .syncing, entryCount: 24)
                    }
                }
            }
    }
}

#Preview("States") {
    VStack(alignment: .leading, spacing: 16) {
        SyncStatusLabel(status: .synced, entryCount: 24)
        SyncStatusLabel(status: .synced, entryCount: 1)
        SyncStatusLabel(status: .synced, entryCount: 0)
        SyncStatusLabel(status: .syncing, entryCount: 24)
        SyncStatusLabel(status: .offline, entryCount: 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .groupedBackground()
}
