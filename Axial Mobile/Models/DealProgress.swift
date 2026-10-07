//
//  DealProgress.swift
//  Axial Mobile
//

import Foundation

/// One stage of the deal funnel. Raw values are the keys of the per-deal
/// `progress` object on `GET /api/intents/sellside/{id}/deals` — mirrors
/// `ISellsideDealProgress` (supply-deals-row.model.ts) and `FUNNEL_STAGES`
/// (deal-flow-funnel.consts.ts).
///
/// `nda_viewed` is left out on purpose: Product took it off the web funnel
/// (2026-07), and the web keeps it commented out for when it returns.
/// `approved` is left out too — the bar *labelled* "Approved" is driven by
/// `pursued`, per Product.
enum FunnelStage: String, CaseIterable, Hashable, Identifiable {
    case teaserSent = "teaser_sent"
    case teaserOpened = "teaser_opened"
    case interested
    case pursued
    case ndaSent = "nda_sent"
    case ndaSigned = "nda_signed"
    case cimSent = "cim_sent"
    case cimViewed = "cim_viewed"
    case ioiReceived = "ioi_received"
    case loiReceived = "loi_received"
    case loiExecuted = "loi_executed"
    case successfullyClosed = "successfully_closed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .teaserSent: "Teaser Sent"
        case .teaserOpened: "Teaser Opened"
        case .interested: "Interested"
        case .pursued: "Approved"
        case .ndaSent: "NDA Sent"
        case .ndaSigned: "NDA Signed"
        case .cimSent: "CIM Sent"
        case .cimViewed: "CIM Viewed"
        case .ioiReceived: "IOI Received"
        case .loiReceived: "LOI Received"
        case .loiExecuted: "LOI Executed"
        case .successfullyClosed: "Successfully Closed"
        }
    }

    /// The teaser stages have no members list worth landing on, so they
    /// don't drill down. `NON_CLICKABLE_FUNNEL_STAGES`.
    var isDrillable: Bool {
        self != .teaserSent && self != .teaserOpened
    }

    /// Stages that count every member. Everything past Interested counts
    /// interested members only, because a seller can mark any member down the
    /// funnel without the buyer ever showing interest, which inflated the deep
    /// bars. `FUNNEL_STAGES_THROUGH_INTERESTED` — deliberately not the same
    /// set as `isDrillable`; the web keeps the two apart too.
    var countsEveryMember: Bool {
        self == .teaserSent || self == .teaserOpened || self == .interested
    }
}

/// A deal's sticky funnel flags: each is true once the deal has *ever*
/// reached that stage, derived server-side from deal history. They're
/// independent — a deal can reach a deep stage without passing every shallow
/// one — which is why the funnel sums them rather than reading a "furthest
/// stage" field.
struct DealProgress: Decodable, Equatable {
    /// Stages reached. Absent and `false` both read as not reached; `null`
    /// (which `approved` uses) does too.
    let reached: Set<FunnelStage>

    init(reached: Set<FunnelStage> = []) {
        self.reached = reached
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var reached: Set<FunnelStage> = []
        for stage in FunnelStage.allCases {
            let key = AnyKey(stage.rawValue)
            if (try? c.decodeIfPresent(Bool.self, forKey: key)) == true {
                reached.insert(stage)
            }
        }
        self.reached = reached
    }

    func has(_ stage: FunnelStage) -> Bool {
        reached.contains(stage)
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
