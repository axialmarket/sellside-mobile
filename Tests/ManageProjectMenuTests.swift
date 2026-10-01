//
//  ManageProjectMenuTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// The Manage Project menu's shape. Held against `manageMenuItems` and
/// `disabled` in fe-app's manage-project.component.ts, and the Copy Deal Link
/// item in project-setup-header.component.ts.
struct ManageProjectMenuTests {

    private func project(
        supplyState: SupplyState = .inMarket,
        intentState: IntentState = .active,
        autoshare: AutoshareState = .off,
        isComplete: Bool = true
    ) -> ProjectDetail {
        ProjectDetail(
            id: "abc", internalName: "Neptune",
            supplyState: supplyState, intentState: intentState,
            autoshareState: autoshare, isComplete: isComplete
        )
    }

    // MARK: - Sharing Settings

    @Test func sharingSettingsIsSplicedOutOfAnArchivedProject() {
        // Web removes the item rather than disabling it — nothing to configure
        // once a deal is off market.
        for state in [IntentState.archived, .underLoi, .closed] {
            let menu = ManageProjectMenu(project: project(intentState: state))
            #expect(!menu.showsSharingSettings, "\(state.rawValue) kept sharing settings")
        }
    }

    @Test func sharingSettingsStaysOnALiveProject() {
        for state in [IntentState.active, .draft, .onHold] {
            #expect(ManageProjectMenu(project: project(intentState: state)).showsSharingSettings)
        }
    }

    @Test func anIncompleteProjectCannotOpenSharingSettings() {
        #expect(ManageProjectMenu(project: project(isComplete: false)).sharingSettingsIsDisabled)
        #expect(!ManageProjectMenu(project: project()).sharingSettingsIsDisabled)
    }

    @Test func anAutoshareIneligibleProjectCannotEither() {
        #expect(ManageProjectMenu(project: project(autoshare: .ineligible)).sharingSettingsIsDisabled)

        for state in AutoshareState.allCases where state != .ineligible {
            #expect(!ManageProjectMenu(project: project(autoshare: state)).sharingSettingsIsDisabled,
                    "\(state.rawValue) disabled sharing settings")
        }
    }

    // MARK: - Copy Deal Link

    @Test func copyDealLinkWaitsForACompleteProject() {
        #expect(project().canCopyDealLink)
        #expect(!project(isComplete: false).canCopyDealLink)
    }

    @Test func anAbsentIsCompleteReadsAsIncomplete() throws {
        // `!intent.isComplete` on an undefined field is true in the web, so a
        // payload without the flag must not unlock the link.
        let decoded = try JSONDecoder().decode(
            ProjectDetail.self,
            from: Data(#"{"id": "abc", "internal_name": "N"}"#.utf8)
        )
        #expect(!decoded.isComplete)
        #expect(!decoded.canCopyDealLink)
    }

    // MARK: - Status submenu

    @Test func theStatusSubmenuIsTheStatusMenuForTheCurrentState() {
        let menu = ManageProjectMenu(project: project(supplyState: .inMarket))
        #expect(menu.statusGroups == ProjectAction.menu(for: .inMarket))
        #expect(menu.statusGroups == [[.reviewingLois, .underLoi, .closed], [.onHold, .dead]])
    }

    @Test func anUnrecognizedStatusLeavesTheSubmenuEmptySoItIsNotOffered() {
        #expect(ManageProjectMenu(project: project(supplyState: .unknown)).statusGroups.isEmpty)
    }
}

