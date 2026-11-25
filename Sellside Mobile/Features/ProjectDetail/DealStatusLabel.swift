//
//  DealStatusLabel.swift
//  Sellside Mobile
//

import SwiftUI

/// A deal's status on the member card: a coloured dot and the status in
/// bold, with no capsule.
///
/// Deliberately not a tag. The card's capsules are the buyer's attribute
/// badges, and a status capsule among them read as one more badge. A dot and
/// bold text read as "where this stands", like a stage marker.
///
/// The web renders statuses through a grid cell renderer with no per-status
/// colour map of its own, so the three colours here are a mobile decision,
/// not a mirror: a closed deal reads as a win, a dead one recedes, and
/// everything live is brand blue. Revisit with design — see
/// docs/CHALLENGES.md #3.
struct DealStatusLabel: View {
    let status: DealStatus

    private var isEnded: Bool { Self.isEnded(status) }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.dotColor(for: status))
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isEnded ? AxialColor.textSecondary : AxialColor.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.label)")
    }

    static func isEnded(_ status: DealStatus) -> Bool {
        switch status {
        case .targetDeclined, .markedTargetDeclined, .targetDeclinedLocked,
             .endedDiscussions, .targetEndedDiscussions, .targetExpired,
             .rejectedAccess, .removedLocked, .archivedLocked:
            true
        default:
            false
        }
    }

    static func dotColor(for status: DealStatus) -> Color {
        if status == .markedClosed { return TagPalette.green.foreground }
        if isEnded(status) { return AxialColor.textPlaceholder }
        return AxialColor.brandPrimary
    }
}

/// "Interested", as a green label rather than a capsule, so it sits with the
/// status instead of among the attribute badges.
struct InterestedLabel: View {
    var body: some View {
        Label("Interested", systemImage: "hand.thumbsup.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TagPalette.green.foreground)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        DealStatusLabel(status: .teaserOpened)
        HStack { DealStatusLabel(status: .targetSignedNda); InterestedLabel() }
        DealStatusLabel(status: .markedReceivedLoi)
        DealStatusLabel(status: .markedClosed)
        DealStatusLabel(status: .targetExpired)
    }
    .padding()
}
