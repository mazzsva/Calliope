//
//  Bundle+AppVersion.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 03/08/26.
//

import Foundation

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        guard let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return version
        }
        return "\(version) (\(build))"
    }
}
