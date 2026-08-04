//
//  EntryDetail.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 24/07/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EntryDetail {
    @Reducer
    enum Destination {
        case alert(AlertState<EntryDetail.Alert>)
        case editEntry(EntryForm)
    }

    enum Alert: Equatable {
        case confirmDeletion
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: Destination.State?
        var entry: Entry
    }

    enum Action {
        case bookmarkButtonTapped
        case delegate(Delegate)
        case deleteButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case editButtonTapped

        @CasePathable
        enum Delegate {
            case didDelete(Entry.ID)
            case didUpdate(Entry)
        }
    }

    @Dependency(\.hapticsClient) var hapticsClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .bookmarkButtonTapped:
                state.entry.isBookmarked.toggle()
                return .merge(
                    .run { _ in await hapticsClient.selection() },
                    .send(.delegate(.didUpdate(state.entry)))
                )

            case .delegate:
                return .none

            case .deleteButtonTapped:
                state.destination = .alert(.confirmDeletion)
                return .none

            case .destination(.presented(.alert(.confirmDeletion))):
                return .send(.delegate(.didDelete(state.entry.id)))

            case .destination(.presented(.editEntry(.delegate(.didSubmit(let entry))))):
                state.destination = nil
                state.entry = entry
                return .merge(
                    .run { _ in await hapticsClient.success() },
                    .send(.delegate(.didUpdate(entry)))
                )

            case .destination:
                return .none

            case .editButtonTapped:
                state.destination = .editEntry(EntryForm.State(mode: .edit(state.entry)))
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension EntryDetail.Destination.State: Equatable {}

extension AlertState where Action == EntryDetail.Alert {
    static let confirmDeletion = AlertState {
        TextState("Delete Entry")
    } actions: {
        ButtonState(role: .destructive, action: .confirmDeletion) {
            TextState("Delete")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("Are you sure you want to delete this entry?")
    }
}
