//
//  SellsideDeal.swift
//  Axial Mobile
//

import Foundation

/// One row from `GET /api/intents/sellside/{intentId}/deals` — a buyside
/// member the project has been shared with.
///
/// Note the path: fe-app's `getSellsideDealsRows` still calls
/// `/api/sellside/deals/{intentId}`, which the deployed API answers with a
/// 404. Trust the API over the web source here (see docs/CHALLENGES.md #11).
///
/// Mirrors fe-app's `ISellsideDealsRowData` (supply-deals-row.model.ts), a
/// ~50-field payload; this decodes only what the dashboard renders and acts
/// on. Everything but `public_id` tolerates absence.
struct SellsideDeal: Decodable, Identifiable, Equatable {
    let publicId: String
    let demandAccountPublicId: String?
    let demandAccountName: String?
    let demandUserName: String?
    var supplyStatus: DealStatus
    var demandIsRead: Bool
    let referralSource: String?
    let isInterested: Bool
    let isAnonymous: Bool

    // Read by the dashboard's action items and funnel.
    let progress: DealProgress
    /// Outreach to this member is gated on the seller's approval.
    let requiresApproval: Bool
    /// A PURSUED history row exists — what the server's `can_send_cim` needs.
    let hasTargetPursued: Bool
    /// A signature record exists, so it survives the deal moving further on.
    let hasSignedNda: Bool
    let hasPendingNdaRedline: Bool

    // Read by the member breakdown chart.
    /// Two-letter account code (`ACCOUNT_TYPES`): "PE", "FO", …
    let demandAccountCode: String?
    /// `"add_on"` when the buyer is a portfolio company.
    let demandClientIntentSubtype: String?
    let capitalSource: CapitalSource?
    /// `buyside_closed_deals.value`, 0 when absent — the web's
    /// `buysideClosedDealsFormatted`.
    let closedDeals: Int

    var id: String { publicId }

    enum CodingKeys: String, CodingKey {
        case publicId = "public_id"
        case demandAccountPublicId = "demand_account_public_id"
        case demandAccountName = "demand_account_name"
        case demandUserName = "demand_user_name"
        case supplyStatus = "supply_status"
        case demandIsRead = "demand_is_read"
        case referral
        case isInterested = "is_interested"
        case isAnonymous = "is_anonymous"
        case progress
        case requiresApproval = "requires_approval"
        case hasTargetPursued = "has_target_pursued"
        case signedNda = "signed_nda"
        case hasPendingNdaRedline = "has_pending_nda_redline"
        case demandAccountCode = "demand_account_code"
        case demandClientIntentSubtype = "demand_client_intent_subtype"
        case capitalSource = "capital_source"
        case buysideClosedDeals = "buyside_closed_deals"
    }

    private enum MetricKeys: String, CodingKey {
        case value
    }

    private enum ReferralKeys: String, CodingKey {
        case referralSource = "referral_source"
    }

    init(
        publicId: String,
        demandAccountPublicId: String? = nil,
        demandAccountName: String? = nil,
        demandUserName: String? = nil,
        supplyStatus: DealStatus = .unknown,
        demandIsRead: Bool = false,
        referralSource: String? = nil,
        isInterested: Bool = false,
        isAnonymous: Bool = false,
        progress: DealProgress = DealProgress(),
        requiresApproval: Bool = false,
        hasTargetPursued: Bool = false,
        hasSignedNda: Bool = false,
        hasPendingNdaRedline: Bool = false,
        demandAccountCode: String? = nil,
        demandClientIntentSubtype: String? = nil,
        capitalSource: CapitalSource? = nil,
        closedDeals: Int = 0
    ) {
        self.publicId = publicId
        self.demandAccountPublicId = demandAccountPublicId
        self.demandAccountName = demandAccountName
        self.demandUserName = demandUserName
        self.supplyStatus = supplyStatus
        self.demandIsRead = demandIsRead
        self.referralSource = referralSource
        self.isInterested = isInterested
        self.isAnonymous = isAnonymous
        self.progress = progress
        self.requiresApproval = requiresApproval
        self.hasTargetPursued = hasTargetPursued
        self.hasSignedNda = hasSignedNda
        self.hasPendingNdaRedline = hasPendingNdaRedline
        self.demandAccountCode = demandAccountCode
        self.demandClientIntentSubtype = demandClientIntentSubtype
        self.capitalSource = capitalSource
        self.closedDeals = closedDeals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publicId = try c.decode(String.self, forKey: .publicId)
        demandAccountPublicId = try c.decodeIfPresent(String.self, forKey: .demandAccountPublicId)
        demandAccountName = try c.decodeIfPresent(String.self, forKey: .demandAccountName)
        demandUserName = try c.decodeIfPresent(String.self, forKey: .demandUserName)
        supplyStatus = try c.decodeIfPresent(DealStatus.self, forKey: .supplyStatus) ?? .unknown
        demandIsRead = try c.decodeIfPresent(Bool.self, forKey: .demandIsRead) ?? false
        isInterested = try c.decodeIfPresent(Bool.self, forKey: .isInterested) ?? false
        isAnonymous = try c.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false

        progress = (try? c.decodeIfPresent(DealProgress.self, forKey: .progress)) ?? DealProgress()
        requiresApproval = (try? c.decodeIfPresent(Bool.self, forKey: .requiresApproval)) ?? false
        hasTargetPursued = (try? c.decodeIfPresent(Bool.self, forKey: .hasTargetPursued)) ?? false
        // The web's `hasSignedNda` is `!!signed_nda`; only presence matters.
        hasSignedNda = (try? c.decodeNil(forKey: .signedNda)) == false
        hasPendingNdaRedline = (try? c.decodeIfPresent(Bool.self, forKey: .hasPendingNdaRedline)) ?? false
        demandAccountCode = try? c.decodeIfPresent(String.self, forKey: .demandAccountCode)
        demandClientIntentSubtype = try? c.decodeIfPresent(String.self, forKey: .demandClientIntentSubtype)
        capitalSource = try? c.decodeIfPresent(CapitalSource.self, forKey: .capitalSource)
        let metric = try? c.nestedContainer(keyedBy: MetricKeys.self, forKey: .buysideClosedDeals)
        closedDeals = (try? metric?.decodeIfPresent(Double.self, forKey: .value)).flatMap { $0 }
            .map { Int($0) } ?? 0

        let referral = try? c.nestedContainer(keyedBy: ReferralKeys.self, forKey: .referral)
        referralSource = try? referral?.decodeIfPresent(String.self, forKey: .referralSource)
    }
}

// MARK: - Derived status

extension SellsideDeal {
    /// A referral the buyer raised themselves, rather than an inbound inquiry.
    /// Mirrors `isReferral && wasBuysideReferral`.
    var isActiveBuysideReferral: Bool {
        guard supplyStatus == .targetRequestedAccess, let referralSource else { return false }
        return referralSource == "deal" || referralSource == "teaser"
    }

    /// What the UI shows, which isn't always `supply_status`. Mirrors
    /// `tableData.displayStatusKey` in supply-deals-row.model.ts:
    ///
    /// - a read teaser reads as "Teaser Opened" — a virtual status the backend
    ///   derives the same way from `supply_status` + `demand_is_read`;
    /// - a buyside referral reads as "Referral Received";
    /// - the `marked_` statuses collapse onto the system status they stand in
    ///   for, so "I sent the NDA" and "the system sent the NDA" read alike.
    var displayStatus: DealStatus {
        if supplyStatus == .sentTeaser, demandIsRead { return .teaserOpened }
        if isActiveBuysideReferral { return .referralReceived }

        switch supplyStatus {
        case .markedSentNda: return .sentNda
        case .markedSentCim: return .sentCim
        case .markedTargetDeclined: return .targetDeclined
        case .markedNdaSigned: return .targetSignedNda
        default: return supplyStatus
        }
    }

    /// Who to show as the counterparty on this row.
    var displayName: String {
        if let name = demandAccountName, !name.isEmpty { return name }
        if let name = demandUserName, !name.isEmpty { return name }
        return isAnonymous ? "Anonymous Buyer" : "Unnamed Member"
    }

    /// Folds in a `deals/supply-marking-status` response. Web does the same
    /// field-by-field merge in `mapDealToSellsideDealsRows` rather than
    /// re-fetching the row.
    func applying(_ update: DealStatusUpdate) -> SellsideDeal {
        var updated = self
        if let status = update.supplyStatus { updated.supplyStatus = status }
        if let isRead = update.demandIsRead { updated.demandIsRead = isRead }
        return updated
    }
}

/// One element of the `POST /api/deals/supply-marking-status` response. That
/// endpoint answers with full deal objects (`IDealData`), not deal *rows* —
/// this takes the fields that actually change.
struct DealStatusUpdate: Decodable, Equatable {
    let id: String
    let supplyStatus: DealStatus?
    let demandIsRead: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case supplyStatus = "supply_status"
        case demandIsRead = "demand_is_read"
    }
}

/// Body for `POST /api/deals/supply-marking-status`. Web posts to the same
/// endpoint for one row or a bulk selection; mobile only sends one today, but
/// the shape is the list either way.
struct MarkDealsRequest: Encodable, Equatable {
    let status: String
    let publicIds: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case publicIds = "public_ids"
    }
}

// MARK: - Dashboard rules

extension SellsideDeal {
    /// Company type for the member breakdown. Portfolio companies of a PE
    /// fund count as corporations — mirrors the private `companyCode` getter
    /// in supply-deals-row.model.ts.
    var companyCode: String? {
        demandClientIntentSubtype == "add_on" && demandAccountCode == "PE" ? "C" : demandAccountCode
    }

    /// The seller set this status by hand rather than the platform.
    /// `isUserMarkedStatus` in deal.constants.ts.
    var isUserMarkedStatus: Bool {
        supplyStatus.rawValue.hasPrefix("marked_")
    }

    /// A redline is waiting on the seller. A hand-marked status hides it,
    /// because the seller has already moved the deal on themselves.
    /// `shouldShowNdaRedline` in deal.constants.ts.
    var showsNdaRedline: Bool {
        hasPendingNdaRedline && !isUserMarkedStatus
    }
}

/// A buyer's capital source. `ECapitalSource` in account.model.ts.
enum CapitalSource: String, Decodable, Hashable {
    case committed
    case dealByDeal = "deal_by_deal"
    case balanceSheet = "balance_sheet"
    case personalWealth = "personal_wealth"
    case other
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CapitalSource(rawValue: raw) ?? .unknown
    }
}

// MARK: - Which list a deal belongs to

extension SellsideDeal {
    /// The three lists a project's deals split into.
    ///
    /// Web reaches for a second endpoint here — its Recommended tab is fed by
    /// `/api/sellside/recommendations/{intentId}` while Contacted and
    /// Interested partition the deals on `is_interested`. The deals payload
    /// already carries enough to tell all three apart, so mobile derives them
    /// from one response instead of paying for two.
    enum Bucket: Hashable {
        /// Axial has put the member forward; nothing has been shared yet.
        case recommended
        /// The teaser is out and the conversation is somewhere in the funnel.
        case contacted
        /// The member has said they're interested.
        case interested
    }

    /// Order matters: `is_interested` wins, because that's what lifts a deal
    /// out of Contacted on the web (`getContactedTargetsRows` filters on
    /// exactly that). What's left is Recommended if it has never been shared,
    /// and Contacted otherwise.
    var bucket: Bucket {
        if isInterested { return .interested }
        if supplyStatus == .recommended || supplyStatus == .notShared { return .recommended }
        return .contacted
    }
}

extension SellsideDeal.Bucket: CaseIterable, Identifiable {
    var id: Self { self }

    /// Funnel order — the order the sections read on the project screen.
    static let allCases: [SellsideDeal.Bucket] = [.recommended, .contacted, .interested]

    var title: String {
        switch self {
        case .recommended: "Recommended"
        case .contacted: "Contacted"
        case .interested: "Interested"
        }
    }

    var emptyMessage: String {
        switch self {
        case .recommended: "No recommendations available for this project yet."
        case .contacted: "No members have been contacted on this project yet."
        case .interested: "No members have expressed interest yet."
        }
    }
}
