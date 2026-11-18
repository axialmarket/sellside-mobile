//
//  ManageProjectMenuTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// The Manage Project menu's shape. Held against `manageMenuItems` in fe-app's
/// manage-project.component.ts, and the Copy Deal Link button in
/// sell-header.component.html.
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

    // MARK: - Copy Deal Link

    @Test func copyDealLinkIsOfferedOnlyWhileTheProjectIsActive() {
        // `canGenerateAxialDirectedLink()`: `intentState === "active"`.
        #expect(project().canCopyDealLink)
        #expect(project(isComplete: false).canCopyDealLink)
        #expect(!project(intentState: .draft).canCopyDealLink)
        #expect(!project(intentState: .underLoi).canCopyDealLink)
    }

    @Test func anAbsentIsCompleteReadsAsIncomplete() throws {
        // `!intent.isComplete` on an undefined field is true in the web, so a
        // payload without the flag reads as incomplete.
        let decoded = try JSONDecoder().decode(
            ProjectDetail.self,
            from: Data(#"{"id": "abc", "internal_name": "N"}"#.utf8)
        )
        #expect(!decoded.isComplete)
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

