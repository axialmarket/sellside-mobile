//
//  FactLabel.swift
//  Axial Mobile
//

import SwiftUI

/// One icon-led fact — "🏢 Private Equity Fund" — as the member card and the
/// deal header show them: a brand-blue icon, close beside the text in the
/// text colour. The icon marks the line; the text carries it.
struct FactLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(AxialColor.brandPrimary)
                .imageScale(.small)
                .frame(width: 18)
            Text(text)
                .foregroundStyle(AxialColor.textPrimary)
                .lineLimit(1)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
