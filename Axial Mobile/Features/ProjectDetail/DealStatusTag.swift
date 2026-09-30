//
//  DealStatusTag.swift
//  Axial Mobile
//

import SwiftUI

/// Deal status capsule.
///
/// The web renders these through a grid cell renderer with no per-status color
/// map of its own, so the three buckets here are a mobile decision, not a
/// mirror: a closed deal reads as a win, a dead one recedes, everything live
/// stays neutral. Revisit with design — see docs/CHALLENGES.md #3.
struct DealStatusTag: View {
    let status: DealStatus

    var body: some View {
        TagCapsule(
            text: status.label,
            palette: Self.palette(for: status),
            isMuted: Self.isEnded(status)
        )
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

    static func palette(for status: DealStatus) -> TagPalette {
        if status == .markedClosed { return .green }
        if isEnded(status) { return .plain }
        return .plain
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        DealStatusTag(status: .teaserOpened)
        DealStatusTag(status: .targetSignedNda)
        DealStatusTag(status: .markedReceivedLoi)
        DealStatusTag(status: .markedClosed)
        DealStatusTag(status: .targetExpired)
    }
    .padding()
}
