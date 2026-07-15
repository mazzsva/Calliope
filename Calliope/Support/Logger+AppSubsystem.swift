//
//  Logger+AppSubsystem.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 15/07/26.
//

import os

extension Logger {
    static let appSubsystem = "com.mazzsva.Calliope"

    init(category: String) {
        self.init(subsystem: Self.appSubsystem, category: category)
    }
}
