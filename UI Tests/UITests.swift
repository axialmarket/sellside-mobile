//
//  UITests.swift
//  UITests
//

import XCTest

/// End-to-end checks of the main flows, against the app's fixture data.
///
/// Each test launches with `-ui-testing` (`UITestMode` in the app): signed
/// in, no Auth0, no network, and `FixtureAPI`'s one project — Project
/// Neptune, in market, with members in every list. So these run anywhere,
/// CI included, without an account or the VPN (CHALLENGES #12).
final class UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    // MARK: - Projects

    @MainActor
    func testTheProjectsListShowsEveryProject() throws {
        XCTAssertTrue(projectCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Project Neptune"].exists)
        XCTAssertTrue(app.staticTexts["Project Atlas"].exists)
    }

    @MainActor
    func testLongPressingAProjectOffersItsStatusChanges() throws {
        XCTAssertTrue(projectCard.waitForExistence(timeout: 5))
        projectCard.press(forDuration: 1.0)
        // In market: Reviewing LOIs is offered, Return to Market isn't. By
        // label: context menu items don't reliably keep their identifiers.
        XCTAssertTrue(app.buttons["Reviewing LOIs"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Return to Market"].exists)
    }

    @MainActor
    func testSwipingAProjectOpensAMemberListOverItsDashboard() throws {
        XCTAssertTrue(projectCard.waitForExistence(timeout: 5))
        projectCard.swipeRight()
        // Neptune's fixture has members in all three lists.
        let interested = app.buttons["Open Interested, 3 members"]
        XCTAssertTrue(interested.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Recommended, 1 member"].exists)
        interested.tap()
        XCTAssertTrue(app.buttons["deals-select"].waitForExistence(timeout: 5))

        // Back lands on the dashboard, not the projects list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["project-section-interested"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSwipingAProjectForStatusOpensASheet() throws {
        XCTAssertTrue(projectCard.waitForExistence(timeout: 5))
        projectCard.swipeLeft()
        app.buttons["project-swipe-status"].tap()
        XCTAssertTrue(app.buttons["project-status-reviewingLois"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["project-status-returnToMarket"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(projectCard.waitForExistence(timeout: 3))
    }

    @MainActor
    func testOpeningAProjectShowsItsDashboard() throws {
        openProject()
        XCTAssertTrue(app.buttons["project-section-interested"].exists)
        XCTAssertTrue(app.buttons["project-section-contacted"].exists)
        XCTAssertTrue(app.buttons["manage-project-menu"].exists)
    }

    // MARK: - Member lists

    @MainActor
    func testSelectModeCountsAndClearsTheSelection() throws {
        openInterestedList()
        let select = app.buttons["deals-select"]
        XCTAssertEqual(select.label, "Select")

        select.tap()
        XCTAssertEqual(select.label, "Select All")
        select.tap()
        // The three interested members.
        XCTAssertTrue(app.staticTexts["3 Selected"].waitForExistence(timeout: 3))
        XCTAssertEqual(select.label, "Deselect All")

        app.buttons["deals-select-done"].tap()
        XCTAssertEqual(select.label, "Select")
    }

    @MainActor
    func testSwipingAMemberOffersMoreActions() throws {
        openInterestedList()
        let card = app.otherElements["deal-card-d2"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.swipeLeft()
        app.buttons["More actions"].tap()
        XCTAssertTrue(app.buttons["deal-actions-close"].waitForExistence(timeout: 3))
        app.buttons["deal-actions-close"].tap()
    }

    @MainActor
    func testAnAccessRequestSwipesRightToPassAndLeftToAccept() throws {
        openInterestedList()
        let card = app.otherElements["deal-card-d3"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        // By label: swipe buttons don't reliably keep their identifiers.
        card.swipeRight()
        XCTAssertTrue(app.buttons["Pass on Member"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Accept Inquiry"].exists)
        card.tap() // closes the swipe without opening the deal

        card.swipeLeft()
        XCTAssertTrue(app.buttons["Accept Inquiry"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Pass on Member"].exists)
    }

    // MARK: - A deal

    @MainActor
    func testADealOpensOnItsProfileWithReplyOnMessages() throws {
        openInterestedList()
        let card = app.otherElements["deal-card-d1"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let profileTab = app.buttons["deal-tab-profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        XCTAssertEqual(profileTab.label, "Company Profile")
        XCTAssertTrue(profileTab.isSelected)
        XCTAssertFalse(app.buttons["deal-reply"].exists)

        // Reply is pinned above the footer on Messages, for a member you can
        // write to.
        app.buttons["deal-tab-messages"].tap()
        XCTAssertTrue(app.buttons["deal-reply"].waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    private var projectCard: XCUIElement {
        app.buttons["project-card-aaabbb"]
    }

    private func openProject() {
        XCTAssertTrue(projectCard.waitForExistence(timeout: 5))
        projectCard.tap()
        XCTAssertTrue(app.buttons["project-section-interested"].waitForExistence(timeout: 5))
    }

    private func openInterestedList() {
        openProject()
        app.buttons["project-section-interested"].tap()
        XCTAssertTrue(app.buttons["deals-select"].waitForExistence(timeout: 5))
    }
}
