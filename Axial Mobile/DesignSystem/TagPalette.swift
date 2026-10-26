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
    /// The web's `leftIcon`, as an SF Symbol.
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
        }
        .labelStyle(TagLabelStyle())
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(palette.background, in: Capsule())
        .foregroundStyle(palette.foreground)
        .opacity(isMuted ? 0.65 : 1)
    }
}

/// Icon and text closer than `.titleAndIcon` sets them, and no gap when
/// there's no icon.
private struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// Lays children out left to right, wrapping to a new line when the next
/// one won't fit — for tag rows whose length depends on the data.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
