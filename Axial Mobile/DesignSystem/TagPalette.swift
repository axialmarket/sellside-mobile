//
//  TagPalette.swift
//  Axial Mobile
//

import SwiftUI

/// The web's tag colors (`_colors.scss` tag tokens), named as fe-app names
/// them so a `tagColor: "green"` in the web source maps here by sight.
enum TagPalette: String {
    case green, yellow, blue, orange, purple, plain

    var background: Color {
        switch self {
        case .green: Color(hex: 0xD9F0E5)
        case .yellow: Color(hex: 0xFCF2D5)
        case .blue: Color(hex: 0xD6E2FD)
        case .orange: Color(hex: 0xFAE4D7)
        case .purple: Color(hex: 0xE8D9FE)
        case .plain: Color(hex: 0xE5E7EB)
        }
    }

    var foreground: Color {
        switch self {
        case .green: Color(hex: 0x215D42)
        case .yellow: Color(hex: 0x574411)
        case .blue: Color(hex: 0x1A387F)
        case .orange: Color(hex: 0x783D1C)
        case .purple: Color(hex: 0x5E2BAB)
        case .plain: AxialColor.textPrimary
        }
    }
}

/// One capsule, one look. Everything tag-shaped goes through this so the
/// project status and a deal status can't drift apart visually.
struct TagCapsule: View {
    let text: String
    let palette: TagPalette
    var isMuted = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(palette.background, in: Capsule())
            .foregroundStyle(palette.foreground)
            .opacity(isMuted ? 0.65 : 1)
    }
}
