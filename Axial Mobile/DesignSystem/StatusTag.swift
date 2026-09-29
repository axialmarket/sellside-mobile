//
//  StatusTag.swift
//  Axial Mobile
//

import SwiftUI

/// Colored status capsule mirroring the web's tag colors
/// (`SELL_INTENT_STATUS_OPTIONS.tagColor` + `_colors.scss` tag tokens).
struct StatusTag: View {
    let state: SupplyState

    var body: some View {
        let colors = Self.colors(for: state)
        Text(state.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(colors.background, in: Capsule())
            .foregroundStyle(colors.text)
    }

    static func colors(for state: SupplyState) -> (background: Color, text: Color) {
        switch state {
        case .inMarket:
            (Color(hex: 0xD9F0E5), Color(hex: 0x215D42))   // green / success
        case .underReview:
            (Color(hex: 0xFCF2D5), Color(hex: 0x574411))   // yellow / alert
        case .readyToShare:
            (Color(hex: 0xD6E2FD), Color(hex: 0x1A387F))   // blue / brand
        case .reviewingLois, .pendingClose:
            (Color(hex: 0xFAE4D7), Color(hex: 0x783D1C))   // orange / warning
        case .underLoi:
            (Color(hex: 0xE8D9FE), Color(hex: 0x5E2BAB))   // purple / info
        case .draft, .closed, .onHold, .dead, .unknown:
            (Color(hex: 0xE5E7EB), AxialColor.textPrimary) // plain
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        StatusTag(state: .inMarket)
        StatusTag(state: .underReview)
        StatusTag(state: .readyToShare)
        StatusTag(state: .reviewingLois)
        StatusTag(state: .underLoi)
        StatusTag(state: .pendingClose)
        StatusTag(state: .draft)
        StatusTag(state: .unknown)
    }
    .padding()
}
