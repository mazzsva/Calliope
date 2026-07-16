//
//  LoggingIssueReporter.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 17/07/26.
//

import IssueReporting
import os

struct LoggingIssueReporter: IssueReporter {
    func reportIssue(
        _ message: @autoclosure () -> String?,
        severity: IssueSeverity,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        let location = "\(fileID):\(line)"
        let message = message() ?? "An issue was reported."
        switch severity {
        case .warning:
            logger.error("\(location, privacy: .public): \(message, privacy: .public)")
        case .error:
            logger.fault("\(location, privacy: .public): \(message, privacy: .public)")
        }
    }
}

private let logger = Logger(category: "IssueReporting")
