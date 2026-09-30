//
//  StatusTag.swift
//  Axial Mobile
//

import SwiftUI

/// Project status capsule, mirroring the web's tag colors
/// (`SELL_INTENT_STATUS_OPTIONS.tagColor`).
struct StatusTag: View {
    let state: SupplyState

    var body: some View {
        TagCapsule(text: state.label, palette: Self.palette(for: state))
    }

    static func palette(for state: SupplyState) -> TagPalette {
        switch state {
        case .inMarket: .green
        case .underReview: .yellow
        case .readyToShare: .blue
        case .reviewingLois, .pendingClose: .orange
        case .underLoi: .purple
        case .draft, .closed, .onHold, .dead, .unknown: .plain
        }
    }

    static func colors(for state: SupplyState) -> (background: Color, text: Color) {
        let palette = palette(for: state)
        return (palette.background, palette.foreground)
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(SupplyState.allCases, id: \.self) { StatusTag(state: $0) }
    }
    .padding()
}
