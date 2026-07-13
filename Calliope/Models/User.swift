//
//  User.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 13/07/26.
//

struct User: Equatable, Sendable {
    let uid: String
    var email: String?
}

extension User {
    static let mock = User(uid: "mock-uid", email: "user@example.com")
}
