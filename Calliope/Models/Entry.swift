//
//  Entry.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 13/07/26.
//

import Dependencies
import Foundation

struct Entry: Equatable, Identifiable, Sendable {
    let id: UUID
    var term: String
    var definition: String
    var isBookmarked: Bool
    let createdAt: Date
    var updatedAt: Date
}

extension Entry {
    static let mock = Entry(
        id: UUID(0),
        term: "Once in a blue moon",
        definition: "Something that happens very rarely.",
        isBookmarked: true,
        createdAt: Date(timeIntervalSince1970: 1_750_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
    )

    static let mocks: [Entry] = [
        .mock,
        .unbookmarkedMock,
        Entry(
            id: UUID(2),
            term: "Low-hanging fruit",
            definition: "The easiest wins, taken first.",
            isBookmarked: false,
            createdAt: Date(timeIntervalSince1970: 1_748_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_748_000_000)
        ),
    ]

    static let unbookmarkedMock = Entry(
        id: UUID(1),
        term: "Burn the candle at both ends",
        definition: "To work early and late until you're exhausted.",
        isBookmarked: false,
        createdAt: Date(timeIntervalSince1970: 1_749_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_749_000_000)
    )
}
