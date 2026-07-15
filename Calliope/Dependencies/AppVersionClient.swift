//
//  AppVersionClient.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct AppVersionClient: Sendable {
    var appVersion: @Sendable () -> String = { "" }
}

extension AppVersionClient: DependencyKey {
    static var liveValue: AppVersionClient {
        AppVersionClient(
            appVersion: {
                let version =
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? "Unknown"
                guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
                    return version
                }
                return "\(version) (\(build))"
            }
        )
    }

    static var previewValue: AppVersionClient {
        AppVersionClient(appVersion: { "1.0" })
    }

    static var testValue: AppVersionClient {
        AppVersionClient()
    }
}

extension DependencyValues {
    var appVersionClient: AppVersionClient {
        get { self[AppVersionClient.self] }
        set { self[AppVersionClient.self] = newValue }
    }
}
