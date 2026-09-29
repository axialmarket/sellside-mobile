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
}
