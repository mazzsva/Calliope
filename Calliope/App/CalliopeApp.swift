//
//  CalliopeApp.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 04/07/26.
//

import ComposableArchitecture
import FirebaseCore
import IssueReporting
import SwiftUI

@main
struct CalliopeApp: App {
    @MainActor
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    init() {
        #if !DEBUG
        // Release builds log reported issues instead of raising runtime warnings
        IssueReporters.current = [LoggingIssueReporter()]
        #endif
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            // Don't run the live app while tests execute in this host
            if !isTesting {
                AppView(store: Self.store)
            }
        }
    }
}
