//
//  AxialColor.swift
//  Axial Mobile
//

import SwiftUI
import UIKit

extension Color {
    /// Color from a 0xRRGGBB value (sRGB).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A colour with a light and a dark value, resolved by the system as the
    /// appearance changes — including mid-session, when the Appearance
    /// setting flips.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: Color(hex: light), dark: Color(hex: dark))
    }
}

/// Axial design tokens, mirrored from fe-app `_colors.scss`, each with its
/// light and dark value. The dark values are the web's own dark theme
/// (packages/tokens/scss/tokens/dark/_colors.scss), by the semantic token
/// named on each line. Hand-copied for the POC — see docs/CHALLENGES.md
/// "Design-token drift".
enum AxialColor {
    // Brand and status fills stay the same in both themes, as on the web.
    static let brandPrimary = Color(hex: 0x326CF4)                     // color-brand-default
    static let brandPressed = Color(hex: 0x2249A6)                     // color-brand-accent
    static let textPrimary = Color(light: 0x2D3138, dark: 0xE5E7EB)    // typography-color-text-primary
    static let textSecondary = Color(light: 0x555C69, dark: 0xA7ADBB)  // typography-color-text-secondary
    static let textPlaceholder = Color(light: 0xA7ADBB, dark: 0x7D879B) // typography-color-text-placeholder
    static let layer1 = Color(light: 0xFFFFFF, dark: 0x2D3138)         // general-layer-01
    static let layer2 = Color(light: 0xFAFAFB, dark: 0x23262C)         // general-layer-02
    static let layer3 = Color(light: 0xEFF1F3, dark: 0x191B1F)         // general-layer-03
    static let border = Color(light: 0xE5E7EB, dark: 0x414651)         // border-color-1 / general-border-01
    /// A brand-tinted fill. The web's `color-brand-hint` stays pale in its
    /// dark theme, which glares on a dark card, so dark takes the theme's
    /// highlight layer instead.
    static let brandSubtle = Color(light: 0xECF1FE, dark: 0x2E3D5E)    // general-layer-01-highlight
    // Form validation.
    static let error = Color(hex: 0xD72746)                            // color-danger-default
    /// The web's danger accent is too dark to read on a dark card; dark
    /// uses the danger highlight.
    static let errorText = Color(light: 0xAC1F38, dark: 0xDF526B)      // danger-accent / danger-highlight
    /// Pale red in light; a red wash in dark, as the web's badges do.
    static let errorSubtle = Color(light: Color(hex: 0xFBECEE), dark: Color(hex: 0xD72746).opacity(0.2))
    static let success = Color(hex: 0x39A292)                          // color-success-default

    // MARK: Surfaces
    //
    // What a screen is built from, by role rather than by layer number, so
    // every screen of cards stacks the same way. Mobile's own mapping: the
    // web puts its white cards on `layer2`, which is fine on a big monitor
    // but on a phone left only a hairline between neighbouring cards.

    /// The ground a screen of cards sits on — projects, dashboard, member
    /// lists, a deal. One step darker than the cards.
    static let canvas = layer3
    /// A card on the canvas (`cardSurface`).
    static let surface = layer1
    /// A well inside a card, such as the project card's counts strip.
    static let inset = layer2
}
