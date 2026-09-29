//
//  SupplyState.swift
//  Axial Mobile
//

import Foundation

/// Sellside project status. Mirrors `IntentSupplyStates` and
/// `SELL_INTENT_STATUS_OPTIONS` in fe-app `sell.constants.ts`.
/// Unrecognized backend values decode to `.unknown` instead of failing.
enum SupplyState: String, Decodable, Hashable {
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
        self = SupplyState(rawValue: raw) ?? .unknown
    }

    /// Mobile section ordering: active statuses first — an approved
    /// reordering of the web's `SELL_INTENT_STATUS_FUNNEL`.
    static let sectionOrder: [SupplyState] = [
        .inMarket, .reviewingLois, .underLoi, .pendingClose,
        .readyToShare, .underReview, .draft, .onHold, .closed, .dead, .unknown,
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
