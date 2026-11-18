//
//  SupplyState.swift
//  Axial Mobile
//

import Foundation

/// Sellside project status. Mirrors `IntentSupplyStates` and
/// `SELL_INTENT_STATUS_OPTIONS` in fe-app `sell.constants.ts`.
/// Unrecognized backend values decode to `.unknown` instead of failing.
nonisolated enum SupplyState: String, Decodable, Hashable, CaseIterable {
    case draft
    case underReview = "under_review"
    case readyToShare = "ready_to_share"
    case inMarket = "in_market"
    case reviewingLois = "reviewing_lois"
    case underLoi = "under_loi"
    case pendingClose = "pending_close"
    case closed
    case onHold = "on_hold"
    case dead
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // `ready_to_activate` is the backend's older name for Ready to
        // Share — the web folds it in the same way (`normalizeSupplyState`,
        // deal-status.constants.ts).
        self = raw == "ready_to_activate" ? .readyToShare : SupplyState(rawValue: raw) ?? .unknown
    }

    /// Section order — `SELL_INTENT_STATUS_FUNNEL` (deal-status.constants.ts),
    /// which the web's projects list, side nav and homepage all sort by. The
    /// web's leading `auto_draft` has no mobile case; it decodes to
    /// `.unknown`, which goes last.
    static let sectionOrder: [SupplyState] = [
        .inMarket, .readyToShare, .draft, .underReview, .reviewingLois,
        .underLoi, .pendingClose, .onHold, .closed, .dead, .unknown,
    ]

    /// Web labels, shortened for capsules where the web is verbose
    /// ("Successfully Closed" → "Closed", "Deal is Dead" → "Dead").
    var label: String {
        switch self {
        case .draft: "Draft"
        case .underReview: "Under Review"
        case .readyToShare: "Ready to Share"
        case .inMarket: "In Market"
        case .reviewingLois: "Reviewing LOIs"
        case .underLoi: "Under LOI"
        case .pendingClose: "Pending Close"
        case .closed: "Closed"
        case .onHold: "On Hold"
        case .dead: "Dead"
        case .unknown: "Unknown"
        }
    }
}
