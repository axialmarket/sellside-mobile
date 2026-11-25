//
//  ProjectAction.swift
//  Sellside Mobile
//

import Foundation

/// A status change available from the dashboard's Manage Project menu.
///
/// Mirrors fe-app's `SELL_INTENT_STATUS_MENU_OPTIONS` (sell.constants.ts) for
/// which items show, and `updateSellIntentState` (intent.api.service.ts) for
/// where each one posts. Both halves are data here rather than branching in a
/// view, so `ProjectActionTests` can hold them against the web's tables — that
/// test is the thing that catches the web changing a rule out from under us.
///
/// Each endpoint answers with the whole intent, so performing an action
/// refreshes local state from its own response. No follow-up GET.
enum ProjectAction: String, CaseIterable, Identifiable {
    case returnToMarket
    case reviewingLois
    case underLoi
    case closed
    case onHold
    case dead

    var id: String { rawValue }

    var label: String {
        switch self {
        case .returnToMarket: "Return to Market"
        case .reviewingLois: "Reviewing LOIs"
        case .underLoi: "Under LOI"
        case .closed: "Successfully Closed"
        case .onHold: "On Hold"
        case .dead: "Deal is Dead"
        }
    }

    /// SF Symbol standing in for the web's Remix icon.
    var systemImage: String {
        switch self {
        case .returnToMarket: "arrow.uturn.backward"
        case .reviewingLois: "doc.text.magnifyingglass"
        case .underLoi: "checkmark.shield"
        case .closed: "trophy"
        case .onHold: "pause.circle"
        case .dead: "xmark.octagon"
        }
    }

    /// Suffix on `POST /api/intents/{id}/…`.
    var path: String {
        switch self {
        case .returnToMarket: "sellside-return-to-market"
        case .reviewingLois: "sellside-reviewing-lois"
        case .underLoi: "sellside-exclusive-loi"
        case .closed: "sellside-closed"
        case .onHold: "sellside-put-on-hold"
        case .dead: "sellside-dead"
        }
    }

    /// These two ask which party the deal is with, so they open a sheet
    /// instead of a confirmation.
    var needsCounterparty: Bool {
        self == .underLoi || self == .closed
    }

    /// The state this moves the project into — what the status tag will read
    /// once the response lands.
    var resultingState: SupplyState {
        switch self {
        case .returnToMarket: .inMarket
        case .reviewingLois: .reviewingLois
        case .underLoi: .underLoi
        case .closed: .closed
        case .onHold: .onHold
        case .dead: .dead
        }
    }

    var confirmationMessage: String {
        switch self {
        case .returnToMarket:
            "This project will be active again and visible to recommended members."
        case .reviewingLois:
            "Mark this project as reviewing LOIs."
        case .onHold:
            "The project will be archived. You can return it to market at any time."
        case .dead:
            "The project will be archived as dead. You can return it to market at any time."
        case .underLoi, .closed:
            "" // these open the counterparty sheet instead
        }
    }
}

// MARK: - Availability

extension ProjectAction {
    /// States this action is offered in — one per `when` predicate in
    /// `SELL_INTENT_STATUS_MENU_OPTIONS`.
    ///
    /// `.unknown` is in none of them. Web has no such case: it's our sentinel
    /// for a `supply_state` this build doesn't recognize, and offering status
    /// transitions out of a state we can't reason about is how you strand a
    /// project. Read-only until the app is taught the new state.
    var availableStates: Set<SupplyState> {
        switch self {
        case .returnToMarket:
            [.reviewingLois, .underLoi, .pendingClose, .closed, .onHold, .dead]
        case .reviewingLois:
            [.draft, .underReview, .readyToShare, .underLoi, .inMarket, .onHold, .dead, .pendingClose]
        case .underLoi:
            [.draft, .underReview, .readyToShare, .pendingClose, .inMarket, .reviewingLois, .onHold, .dead]
        case .closed:
            // Web: `supplyState !== CLOSED`, i.e. every other known state.
            Set(SupplyState.allCases).subtracting([.closed, .unknown])
        case .onHold:
            [.draft, .underReview, .readyToShare, .pendingClose, .inMarket, .reviewingLois, .underLoi, .dead]
        case .dead:
            [.draft, .underReview, .readyToShare, .pendingClose, .inMarket, .reviewingLois, .underLoi, .onHold]
        }
    }

    func isAvailable(in state: SupplyState) -> Bool {
        availableStates.contains(state)
    }

    /// Menu layout, matching where the web puts its separators. Rendered as
    /// `Section`s so the grouping survives the translation to a SwiftUI Menu.
    static let groups: [[ProjectAction]] = [
        [.returnToMarket],
        [.reviewingLois, .underLoi, .closed],
        [.onHold, .dead],
    ]

    /// The menu for a given status: groups filtered to what's available, empty
    /// groups dropped so no stray separators survive.
    static func menu(for state: SupplyState) -> [[ProjectAction]] {
        groups
            .map { $0.filter { $0.isAvailable(in: state) } }
            .filter { !$0.isEmpty }
    }
}
