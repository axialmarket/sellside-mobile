//
//  ProjectActionTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

/// Held against fe-app's `SELL_INTENT_STATUS_MENU_OPTIONS` (sell.constants.ts)
/// and `updateSellIntentState` (intent.api.service.ts). If the web changes a
/// rule, this is what should go red.
struct ProjectActionTests {

    // MARK: - Availability, one case per web `when` predicate

    @Test func returnToMarketOnlyFromArchivedOrWonDownStates() {
        #expect(ProjectAction.returnToMarket.availableStates == [
            .reviewingLois, .underLoi, .pendingClose, .closed, .onHold, .dead,
        ])
    }

    @Test func closedIsOfferedFromEveryKnownStateButClosed() {
        // Web: `when: (supplyState) => supplyState !== IntentSupplyStates.CLOSED`
        let expected = Set(SupplyState.allCases).subtracting([.closed, .unknown])
        #expect(ProjectAction.closed.availableStates == expected)
        #expect(!ProjectAction.closed.isAvailable(in: .closed))
    }

    @Test func noActionIsOfferedForAnUnrecognizedState() {
        // `.unknown` is ours, not the web's — a supply_state this build doesn't
        // know. Transitioning out of it would be guessing.
        for action in ProjectAction.allCases {
            #expect(!action.isAvailable(in: .unknown), "\(action.rawValue) offered in .unknown")
        }
        #expect(ProjectAction.menu(for: .unknown).isEmpty)
    }

    @Test func noActionOffersTheStateTheProjectIsAlreadyIn() {
        for action in ProjectAction.allCases {
            #expect(
                !action.isAvailable(in: action.resultingState),
                "\(action.rawValue) offered while already \(action.resultingState.rawValue)"
            )
        }
    }

    // MARK: - Menu shape

    @Test func inMarketOffersTheForwardMovesOnly() {
        let menu = ProjectAction.menu(for: .inMarket)
        #expect(menu == [[.reviewingLois, .underLoi, .closed], [.onHold, .dead]])
    }

    @Test func aClosedProjectCanOnlyReturnToMarketOrBeArchived() {
        #expect(ProjectAction.menu(for: .closed) == [[.returnToMarket], [.onHold, .dead]])
    }

    @Test func draftCannotReturnToMarket() {
        let menu = ProjectAction.menu(for: .draft)
        #expect(!menu.flatMap(\.self).contains(.returnToMarket))
    }

    @Test func emptyGroupsNeverLeaveAStraySeparator() {
        for state in SupplyState.allCases {
            #expect(ProjectAction.menu(for: state).allSatisfy { !$0.isEmpty })
        }
    }

    // MARK: - Endpoints

    @Test func pathsMatchTheWebsStateChangeEndpoints() {
        #expect(ProjectAction.returnToMarket.path == "sellside-return-to-market")
        #expect(ProjectAction.onHold.path == "sellside-put-on-hold")
        #expect(ProjectAction.reviewingLois.path == "sellside-reviewing-lois")
        #expect(ProjectAction.underLoi.path == "sellside-exclusive-loi")
        #expect(ProjectAction.closed.path == "sellside-closed")
        #expect(ProjectAction.dead.path == "sellside-dead")
    }

    @Test func onlyTheTwoCounterpartyActionsCarryABody() {
        // Web passes `counterpartyInfo` for exactly these two and `null` otherwise.
        let carrying = ProjectAction.allCases.filter(\.needsCounterparty)
        #expect(carrying == [.underLoi, .closed])
    }
}
