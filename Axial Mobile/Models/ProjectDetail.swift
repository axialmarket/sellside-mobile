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
nonisolated struct ProjectDetail: Decodable, Identifiable, Equatable {
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

    // Read by the dashboard's action items and funnel.
    /// Outreach on this project is gated on a pitch (`requires_approval`).
    let requiresApproval: Bool
    /// `cim_type`; nil when the seller hasn't chosen one.
    let cimType: CimType?
    /// An uploaded CIM document or a linked one — something a member can view.
    /// `SellsideIntent.hasCim`.
    let hasCim: Bool
    /// Follow-up notes count as enabled once `follow_up.message` is set — the
    /// rule the backend and the web's marketing settings both use.
    let hasFollowUp: Bool
    /// Bumped by every supply-side action, so it's the "last activity" the
    /// stale-project nudge and the backend's stale-deal email both measure.
    let updatedAt: Date?
    /// `company.financials`, reduced to the two fields the stale-financials
    /// rule reads.
    let financials: [FinancialPeriod]
    /// `company.fiscal_year_end_month`, 1–12. Nil when unset.
    let fiscalYearEndMonth: Int?

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
        case requiresApproval = "requires_approval"
        case cimType = "cim_type"
        case linkedCim = "linked_cim"
        case documents
        case followUp = "follow_up"
        case updatedAt = "updated_at"
        case company
    }

    private enum FollowUpKeys: String, CodingKey { case message }
    private enum CompanyKeys: String, CodingKey {
        case financials
        case fiscalYearEndMonth = "fiscal_year_end_month"
    }
    private struct Document: Decodable { let type: String? }

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
        inboundInquiryDate: Date? = nil,
        requiresApproval: Bool = false,
        cimType: CimType? = nil,
        hasCim: Bool = false,
        hasFollowUp: Bool = false,
        updatedAt: Date? = nil,
        financials: [FinancialPeriod] = [],
        fiscalYearEndMonth: Int? = nil
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
        self.requiresApproval = requiresApproval
        self.cimType = cimType
        self.hasCim = hasCim
        self.hasFollowUp = hasFollowUp
        self.updatedAt = updatedAt
        self.financials = financials
        self.fiscalYearEndMonth = fiscalYearEndMonth
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

        requiresApproval = (try? c.decodeIfPresent(Bool.self, forKey: .requiresApproval)) ?? false
        cimType = try? c.decodeIfPresent(CimType.self, forKey: .cimType)
        let documents = (try? c.decodeIfPresent([Document].self, forKey: .documents)) ?? []
        let linkedCim = (try? c.decodeIfPresent(String.self, forKey: .linkedCim)) ?? nil
        hasCim = documents.contains { $0.type == "OM" } || !(linkedCim ?? "").isEmpty
        let followUp = try? c.nestedContainer(keyedBy: FollowUpKeys.self, forKey: .followUp)
        // The web tests `!followUp?.message`, so an empty message is off too.
        let followUpMessage = (try? followUp?.decodeIfPresent(String.self, forKey: .message)) ?? nil
        hasFollowUp = !(followUpMessage ?? "").isEmpty
        updatedAt = EpochDate.decode(c, forKey: .updatedAt)
        let company = try? c.nestedContainer(keyedBy: CompanyKeys.self, forKey: .company)
        financials = ((try? company?.decodeIfPresent([FinancialPeriod].self, forKey: .financials)) ?? nil) ?? []
        fiscalYearEndMonth = (try? company?.decodeIfPresent(Int.self, forKey: .fiscalYearEndMonth)) ?? nil
    }
}

/// How the seller is supplying their CIM. `CimType` in
/// sellside-intent.interface.ts.
nonisolated enum CimType: String, Decodable, Hashable {
    case custom
    case linked
    case waive
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CimType(rawValue: raw) ?? .unknown
    }
}

/// One row of `company.financials` — the two fields the stale-financials rule
/// needs out of the web's `FinancialRow`.
nonisolated struct FinancialPeriod: Decodable, Equatable {
    /// A four-digit year, `"ltm"`, or `"na"`.
    let timePeriod: String
    /// Saved as a projection rather than an actual.
    let isEstimated: Bool

    init(timePeriod: String, isEstimated: Bool) {
        self.timePeriod = timePeriod
        self.isEstimated = isEstimated
    }

    enum CodingKeys: String, CodingKey {
        case timePeriod = "time_period"
        case isEstimated = "is_estimated"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timePeriod = (try? c.decodeIfPresent(String.self, forKey: .timePeriod)) ?? ""
        isEstimated = (try? c.decodeIfPresent(Bool.self, forKey: .isEstimated)) ?? false
    }

    /// `isYearPeriod` in financials.helpers.ts.
    var year: Int? {
        guard timePeriod.count == 4, timePeriod.allSatisfy(\.isASCII), timePeriod.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(timePeriod)
    }
}

// MARK: - Dashboard rules

extension ProjectDetail {
    /// Whole days since the last supply-side action, nil when unknown, never
    /// negative. `SellsideIntent.daysSinceLastActivity`.
    func daysSinceLastActivity(now: Date) -> Int? {
        guard let updatedAt else { return nil }
        let elapsed = now.timeIntervalSince(updatedAt)
        return elapsed > 0 ? Int(elapsed / 86_400) : 0
    }

    /// Years saved as projections whose fiscal year has since ended — figures
    /// due to be replaced with actuals. Ascending and distinct.
    /// `staleEstimatedYears` in financials.helpers.ts, with the modal's
    /// December fallback for a project with no fiscal year end set.
    func staleFinancialYears(now: Date, calendar: Calendar = .current) -> [Int] {
        let fyEnd = fiscalYearEndMonth ?? 12
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard let year = parts.year, let month = parts.month else { return [] }
        // `mostRecentCompletedFyYear`.
        let mostRecentCompleted = month > fyEnd ? year : year - 1
        let years = financials.compactMap { $0.isEstimated ? $0.year : nil }
            .filter { $0 <= mostRecentCompleted }
        return Array(Set(years)).sorted()
    }
}
