//
//  HapticsClient.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import Dependencies
import DependenciesMacros
import UIKit

@DependencyClient
struct HapticsClient: Sendable {
    var selection: @Sendable () async -> Void
    var success: @Sendable () async -> Void
    var warning: @Sendable () async -> Void
}

extension HapticsClient: DependencyKey {
    static var liveValue: HapticsClient {
        HapticsClient(
            selection: { await FeedbackGenerators.shared.selectionChanged() },
            success: { await FeedbackGenerators.shared.notify(.success) },
            warning: { await FeedbackGenerators.shared.notify(.warning) }
        )
    }

    static var previewValue: HapticsClient {
        HapticsClient(selection: {}, success: {}, warning: {})
    }

    static var testValue: HapticsClient {
        HapticsClient()
    }
}

extension DependencyValues {
    var hapticsClient: HapticsClient {
        get { self[HapticsClient.self] }
        set { self[HapticsClient.self] = newValue }
    }
}

@MainActor
private final class FeedbackGenerators {
    static let shared = FeedbackGenerators()

    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    func selectionChanged() {
        selection.selectionChanged()
        // Re-prime the generator so the next feedback fires without latency
        selection.prepare()
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
        notification.prepare()
    }
}
