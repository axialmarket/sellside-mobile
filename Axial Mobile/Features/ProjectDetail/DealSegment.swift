//
//  DealSegment.swift
//  Axial Mobile
//

import Foundation

/// A filtered slice of a project's members that the dashboard can drill into
/// — an action item's "these members", or one funnel stage.
///
/// On the web each of these is the Interested tab opened with a grid filter
/// in the URL. Mobile has no grid, so the filter is a predicate here instead,
/// and the same predicate feeds both the dashboard's count and the list it
/// opens. That's the web's own rule ("the single source for both the count
/// and the pre-selection, so the two can never disagree"), kept by
/// construction rather than by matching two filters.
enum DealSegment: Hashable {
    /// Inquiries and referrals awaiting the seller's accept or pass.
    case pendingApproval
    /// NDA redlines waiting on the seller.
    case ndaRedlines
    /// Signed the NDA, eligible for the CIM, and not sent it yet.
    case awaitingCim
    /// Members who ever reached one funnel stage.
    case funnelStage(FunnelStage)

    var title: String {
        switch self {
        case .pendingApproval: "Awaiting Approval"
        case .ndaRedlines: "NDA Redlines"
        case .awaitingCim: "Awaiting CIM"
        case .funnelStage(let stage): stage.label
        }
    }

    var emptyMessage: String {
        switch self {
        case .pendingApproval: "No members are awaiting approval."
        case .ndaRedlines: "No NDA redlines are waiting on you."
        case .awaitingCim: "No members are waiting for the CIM."
        case .funnelStage(let stage): "No members have reached \(stage.label)."
        }
    }

    /// The deals in this segment, out of everything the project holds.
    func deals(in dashboard: ProjectDashboard) -> [SellsideDeal] {
        switch self {
        case .funnelStage(let stage):
            // The web drills to the Interested tab filtered on this stage's
            // sticky flag (`getFunnelStageLink`), so the list is interested
            // members only — even for the Interested stage itself, whose bar
            // counts everyone. A known, mirrored mismatch.
            dashboard.interestedDeals.filter { $0.progress.has(stage) }
        default:
            dashboard.deals.filter(matches)
        }
    }

    func matches(_ deal: SellsideDeal) -> Bool {
        switch self {
        case .pendingApproval:
            // Unfiltered by pursuit on purpose: approving is what writes
            // `has_target_pursued`, so a pursued filter would zero this.
            // `pendingApprovalRows` in sell-dashboard.store.ts.
            deal.supplyStatus == .targetRequestedAccess
        case .ndaRedlines:
            deal.showsNdaRedline
        case .awaitingCim:
            // Gated on pursuit — stricter than the funnel's interested rule.
            // The server's `can_send_cim` needs a PURSUED history row, and a
            // single ineligible member fails a bulk send for everyone.
            // `signedAwaitingCimRows`.
            deal.hasTargetPursued
                && (deal.supplyStatus == .targetSignedNda || deal.supplyStatus == .markedNdaSigned)
        case .funnelStage(let stage):
            deal.isInterested && deal.progress.has(stage)
        }
    }
}
