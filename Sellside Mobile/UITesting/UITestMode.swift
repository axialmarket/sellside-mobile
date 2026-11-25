//
//  UITestMode.swift
//  Sellside Mobile
//

#if DEBUG
import Foundation

/// The seam UI tests run through (CHALLENGES #12). Launched with
/// `-ui-testing`, the app starts signed in without Auth0 and reads its data
/// from `FixtureAPI` instead of the network, so a test needs no account, no
/// VPN and no live API. Debug builds only: none of this ships.
enum UITestMode {
    static let launchArgument = "-ui-testing"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}
#endif
