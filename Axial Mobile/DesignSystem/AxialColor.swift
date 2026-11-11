//
//  AxialColor.swift
//  Axial Mobile
//

import SwiftUI

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
}

/// Axial design tokens, mirrored from fe-app `_colors.scss`.
/// Hand-copied for the POC — see docs/CHALLENGES.md "Design-token drift".
enum AxialColor {
    static let brandPrimary = Color(hex: 0x326CF4)     // $brand-primary / $blue-500
    static let brandPressed = Color(hex: 0x2249A6)     // $blue-600
    static let textPrimary = Color(hex: 0x2D3138)      // $text-primary / $grey-800
    static let textSecondary = Color(hex: 0x555C69)    // $text-secondary / $grey-600
    static let textPlaceholder = Color(hex: 0xA7ADBB)  // $text-placeholder / $grey-400
    static let layer1 = Color(hex: 0xFFFFFF)           // $layer-1
    static let layer2 = Color(hex: 0xFAFAFB)           // $layer-2 / $grey-25
    static let layer3 = Color(hex: 0xEFF1F3)           // $layer-3 / $grey-50
    static let border = Color(hex: 0xE5E7EB)           // $border-color-1
    static let brandSubtle = Color(hex: 0xECF1FE)      // $blue-050
    // Form validation — packages/tokens base _colors.scss.
    static let error = Color(hex: 0xD72746)            // $red-500
    static let errorText = Color(hex: 0xAC1F38)        // $red-600
    static let errorSubtle = Color(hex: 0xFBECEE)      // $red-050
    static let success = Color(hex: 0x39A292)          // $green-500

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
