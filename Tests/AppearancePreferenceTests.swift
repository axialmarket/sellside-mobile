//
//  AppearancePreferenceTests.swift
//  Tests
//

import Testing
import UIKit
@testable import Sellside_Mobile

/// Mobile's own: the Account sheet's Appearance setting.
struct AppearancePreferenceTests {

    /// These are what `UserDefaults` holds. Renaming one would quietly reset
    /// everyone's choice to System.
    @Test func storedValuesStayPut() {
        #expect(AppearancePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
    }

    @Test func systemHandsTheChoiceBackToTheDevice() {
        #expect(AppearancePreference.system.interfaceStyle == .unspecified)
        #expect(AppearancePreference.light.interfaceStyle == .light)
        #expect(AppearancePreference.dark.interfaceStyle == .dark)
    }
}
