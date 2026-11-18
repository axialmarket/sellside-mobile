//
//  UITestsLaunchTests.swift
//  UITests
//
//  Created by Matthew Sinex on 11/20/25.
//

import XCTest

final class UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        // Fixture mode, so the screenshot is the projects list rather than
        // the sign-in screen (see UITests).
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
