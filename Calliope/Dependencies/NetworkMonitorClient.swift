//
//  NetworkMonitorClient.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import Dependencies
import DependenciesMacros
import Network
import os

@DependencyClient
struct NetworkMonitorClient: Sendable {
    var connectivityChanges: @Sendable () -> AsyncStream<Bool> = { AsyncStream { _ in } }
}

extension NetworkMonitorClient: DependencyKey {
    static var liveValue: NetworkMonitorClient {
        NetworkMonitorClient(
            connectivityChanges: {
                AsyncStream { continuation in
                    let monitor = NWPathMonitor()
                    monitor.pathUpdateHandler = { path in
                        continuation.yield(path.status == .satisfied)
                    }
                    continuation.onTermination = { _ in
                        monitor.cancel()
                    }
                    monitor.start(queue: DispatchQueue(label: "\(Logger.appSubsystem).NetworkMonitor"))
                }
            }
        )
    }

    static var previewValue: NetworkMonitorClient {
        NetworkMonitorClient(
            connectivityChanges: {
                AsyncStream { continuation in
                    continuation.yield(true)
                }
            }
        )
    }

    static var testValue: NetworkMonitorClient {
        NetworkMonitorClient()
    }
}

extension DependencyValues {
    var networkMonitorClient: NetworkMonitorClient {
        get { self[NetworkMonitorClient.self] }
        set { self[NetworkMonitorClient.self] = newValue }
    }
}
