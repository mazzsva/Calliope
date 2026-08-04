//
//  Entry.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 13/07/26.
//

import Dependencies
import Foundation

struct Entry: Equatable, Identifiable, Sendable {
    let createdAt: Date
    var definition: String
    let id: UUID
    var isBookmarked: Bool
    var term: String
    var updatedAt: Date
}

extension Entry {
    static let mock = Entry(
        createdAt: Date(timeIntervalSince1970: 1_750_000_000),
        definition: "Something that happens very rarely.",
        id: UUID(0),
        isBookmarked: true,
        term: "Once in a blue moon",
        updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
    )

    static let mocks: [Entry] = [
        .mock,
        .unbookmarkedMock,
        Entry(
            createdAt: Date(timeIntervalSince1970: 1_748_000_000),
            definition: "The easiest wins, taken first.",
            id: UUID(2),
            isBookmarked: false,
            term: "Low-hanging fruit",
            updatedAt: Date(timeIntervalSince1970: 1_748_000_000)
        ),
    ]

    static let unbookmarkedMock = Entry(
        createdAt: Date(timeIntervalSince1970: 1_749_000_000),
        definition: "To work early and late until you're exhausted.",
        id: UUID(1),
        isBookmarked: false,
        term: "Burn the candle at both ends",
        updatedAt: Date(timeIntervalSince1970: 1_749_000_000)
    )
}
