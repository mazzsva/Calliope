//
//  EntryForm.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 20/07/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EntryForm {
    static let maxDefinitionUTF8Count = 40_000
    static let maxTermUTF8Count = 800

    @CasePathable
    enum Mode: Equatable {
        case create
        case edit(Entry)
    }

    @ObservableState
    struct State: Equatable {
        var definition: String
        let mode: Mode
        var term: String

        init(mode: Mode) {
            self.mode = mode
            switch mode {
            case .create:
                definition = ""
                term = ""
            case .edit(let entry):
                definition = entry.definition
                term = entry.term
            }
        }

        var isCreating: Bool {
            mode.is(\.create)
        }

        var isSubmittable: Bool {
            !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case dismissButtonTapped
        case saveButtonTapped

        @CasePathable
        enum Delegate {
            case didSubmit(Entry)
        }
    }

    @Dependency(\.date.now) var now
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.definition):
                state.definition = String(state.definition.prefix(utf8Count: Self.maxDefinitionUTF8Count))
                return .none

            case .binding(\.term):
                state.term = String(state.term.prefix(utf8Count: Self.maxTermUTF8Count))
                return .none

            case .binding:
                return .none

            case .delegate:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss() }

            case .saveButtonTapped:
                guard state.isSubmittable else { return .none }
                let term = state.term.trimmingCharacters(in: .whitespacesAndNewlines)
                let definition = state.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry: Entry
                switch state.mode {
                case .create:
                    entry = Entry(
                        id: uuid(),
                        term: term,
                        definition: definition,
                        isBookmarked: false,
                        createdAt: now,
                        updatedAt: now
                    )
                case .edit(let original):
                    entry = Entry(
                        id: original.id,
                        term: term,
                        definition: definition,
                        isBookmarked: original.isBookmarked,
                        createdAt: original.createdAt,
                        updatedAt: now
                    )
                }
                return .send(.delegate(.didSubmit(entry)))
            }
        }
    }
}

extension String {
    fileprivate func prefix(utf8Count: Int) -> Substring {
        guard utf8.count > utf8Count else { return self[...] }
        var count = 0
        var end = startIndex
        while end < endIndex {
            let next = index(after: end)
            count += self[end ..< next].utf8.count
            guard count <= utf8Count else { break }
            end = next
        }
        return self[..<end]
    }
}
