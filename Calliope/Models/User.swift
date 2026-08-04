//
//  User.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 13/07/26.
//

struct User: Equatable, Sendable {
    var email: String?
    let uid: String
}

extension User {
    static let mock = User(email: "user@example.com", uid: "mock-uid")
}
