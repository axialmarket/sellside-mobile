//
//  ProjectDetail.swift
//  Axial Mobile
//

import Foundation

/// One project from `GET /api/intents/{id}`. Mirrors fe-app's `IIntentData`
/// (intent.model.ts) — a ~60-field payload — decoding only what the mobile
/// dashboard renders. Lenient by design: everything except `id` and
/// `internal_name` tolerates absence.
///
/// This is also the shape every *mutation* answers with: `PATCH
/// /api/intents/{id}` returns `{ intent: IIntentData, … }` and the
/// status-change POSTs return the intent itself. Those responses go through
/// `ProjectDashboardStore.apply(_:)` rather than triggering a re-fetch.
struct ProjectDetail: Decodable, Identifiable, Equatable {
    /// Always hyphen-stripped — see `IntentID`.
    let id: String
    let internalName: String
    let supplyState: SupplyState
    let intentState: IntentState
    let autoshareState: AutoshareState
    let autoshareExpiresAt: Date?
    let isInboundInquiryEnabled: Bool
    let isComplete: Bool

    // Milestone dates. Which one the status detail reads depends on the
    // status — see `SupplyState.statusDateField`.
    let lastDraftDate: Date?
    let inReviewDate: Date?
    let inMarketDate: Date?
    let underLoiDate: Date?
    let inboundInquiryDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case internalName = "internal_name"
        case supplyState = "supply_state"
        case intentState = "intent_state"
        case autoshareState = "autoshare_state"
        case autoshareExpiresAt = "autoshare_expires_at"
        case isInboundInquiryEnabled = "is_inbound_inquiry_enabled"
        case isComplete = "is_complete"
        case lastDraftDate = "last_draft_date"
        case inReviewDate = "in_review_date"
        case inMarketDate = "in_market_date"
        case underLoiDate = "under_loi_date"
        case inboundInquiryDate = "inbound_inquiry_date"
    }

    init(
        id: String,
        internalName: String,
        supplyState: SupplyState = .unknown,
        intentState: IntentState = .active,
        autoshareState: AutoshareState = .off,
        autoshareExpiresAt: Date? = nil,
        isInboundInquiryEnabled: Bool = false,
        isComplete: Bool = true,
        lastDraftDate: Date? = nil,
        inReviewDate: Date? = nil,
        inMarketDate: Date? = nil,
        underLoiDate: Date? = nil,
        inboundInquiryDate: Date? = nil
    ) {
        self.id = IntentID.normalized(id)
        self.internalName = internalName
        self.supplyState = supplyState
        self.intentState = intentState
        self.autoshareState = autoshareState
        self.autoshareExpiresAt = autoshareExpiresAt
        self.isInboundInquiryEnabled = isInboundInquiryEnabled
        self.isComplete = isComplete
        self.lastDraftDate = lastDraftDate
        self.inReviewDate = inReviewDate
        self.inMarketDate = inMarketDate
        self.underLoiDate = underLoiDate
        self.inboundInquiryDate = inboundInquiryDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = IntentID.normalized(try c.decode(String.self, forKey: .id))
        internalName = try c.decode(String.self, forKey: .internalName)
        // Typed `IntentSupplyState | null` on the web (null on buyside intents).
        supplyState = try c.decodeIfPresent(SupplyState.self, forKey: .supplyState) ?? .unknown
        intentState = try c.decodeIfPresent(IntentState.self, forKey: .intentState) ?? .unknown
        autoshareState = try c.decodeIfPresent(AutoshareState.self, forKey: .autoshareState) ?? .off
        isInboundInquiryEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .isInboundInquiryEnabled) ?? false
        // Absent reads as incomplete, matching `!intent.isComplete` on an
        // undefined field in the web.
        isComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false

        autoshareExpiresAt = EpochDate.decode(c, forKey: .autoshareExpiresAt)
        lastDraftDate = EpochDate.decode(c, forKey: .lastDraftDate)
        inReviewDate = EpochDate.decode(c, forKey: .inReviewDate)
        inMarketDate = EpochDate.decode(c, forKey: .inMarketDate)
        underLoiDate = EpochDate.decode(c, forKey: .underLoiDate)
        inboundInquiryDate = EpochDate.decode(c, forKey: .inboundInquiryDate)
    }
}
