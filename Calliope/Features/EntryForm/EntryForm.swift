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

    @ObservableState
    struct State: Equatable {
        var definition: String
        let entry: Entry?
        var term: String

        init(entry: Entry? = nil) {
            self.entry = entry
            definition = entry?.definition ?? ""
            term = entry?.term ?? ""
        }

        var isCreating: Bool {
            entry == nil
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
                let original = state.entry
                let entry = Entry(
                    createdAt: original?.createdAt ?? now,
                    definition: definition,
                    id: original?.id ?? uuid(),
                    isBookmarked: original?.isBookmarked ?? false,
                    term: term
                )
                return .send(.delegate(.didSubmit(entry)))
            }
        }
    }
}

extension String {
    fileprivate func prefix(utf8Count: Int) -> Substring {
        guard utf8.count > utf8Count else { return self[...] }
        var end = utf8.index(utf8.startIndex, offsetBy: utf8Count)
        while String.Index(end, within: self) == nil {
            end = utf8.index(before: end)
        }
        return self[..<end]
    }
}
