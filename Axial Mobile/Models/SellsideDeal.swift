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

    // Read by the member card.
    /// The buyer's client, when the account is acting for one (a banker's
    /// client, or a fund's portfolio company).
    let demandClientName: String?
    /// The member's job title.
    let title: String?
    let city: String?
    let stateProvince: String?
    let country: String?
    let lastMessage: String?
    let lastMessageFromFullName: String?
    let lastMessageAt: Date?
    let newMessageCount: Int
    /// `demand_user_ratings.average`; nil when nobody has rated them.
    let averageRating: Double?
    /// When the status last moved — `supply_updated_at`, else `updated_at`,
    /// else `created_at`. The web's `statusDate`, its "Last Updated" column.
    let statusDate: Date?
    /// Badges the backend assigns the buyer, in its order. Values this build
    /// doesn't know are dropped rather than shown blank.
    let attributes: [BuysideAttribute]

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
        case demandClientName = "demand_client_name"
        case title
        case city = "demand_account_city"
        case stateProvince = "demand_account_state_province"
        case country = "demand_account_country"
        case lastMessage = "last_message"
        case lastMessageFromFullName = "last_message_from_full_name"
        case lastMessageAt = "last_message_at"
        case newMessageCount = "new_message_count"
        case demandUserRatings = "demand_user_ratings"
        case supplyUpdatedAt = "supply_updated_at"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case buysideAttributes = "buyside_attributes"
    }

    private enum RatingKeys: String, CodingKey {
        case average
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
        closedDeals: Int = 0,
        demandClientName: String? = nil,
        title: String? = nil,
        city: String? = nil,
        stateProvince: String? = nil,
        country: String? = nil,
        lastMessage: String? = nil,
        lastMessageFromFullName: String? = nil,
        lastMessageAt: Date? = nil,
        newMessageCount: Int = 0,
        averageRating: Double? = nil,
        statusDate: Date? = nil,
        attributes: [BuysideAttribute] = []
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
        self.demandClientName = demandClientName
        self.title = title
        self.city = city
        self.stateProvince = stateProvince
        self.country = country
        self.lastMessage = lastMessage
        self.lastMessageFromFullName = lastMessageFromFullName
        self.lastMessageAt = lastMessageAt
        self.newMessageCount = newMessageCount
        self.averageRating = averageRating
        self.statusDate = statusDate
        self.attributes = attributes
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

        demandClientName = (try? c.decodeIfPresent(String.self, forKey: .demandClientName)) ?? nil
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
        city = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? nil
        stateProvince = (try? c.decodeIfPresent(String.self, forKey: .stateProvince)) ?? nil
        country = (try? c.decodeIfPresent(String.self, forKey: .country)) ?? nil
        lastMessage = (try? c.decodeIfPresent(String.self, forKey: .lastMessage)) ?? nil
        lastMessageFromFullName = (try? c.decodeIfPresent(String.self, forKey: .lastMessageFromFullName)) ?? nil
        lastMessageAt = EpochDate.decode(c, forKey: .lastMessageAt)
        newMessageCount = (try? c.decodeIfPresent(Int.self, forKey: .newMessageCount)) ?? 0
        let ratings = try? c.nestedContainer(keyedBy: RatingKeys.self, forKey: .demandUserRatings)
        averageRating = (try? ratings?.decodeIfPresent(Double.self, forKey: .average)) ?? nil
        statusDate = EpochDate.decode(c, forKey: .supplyUpdatedAt)
            ?? EpochDate.decode(c, forKey: .updatedAt)
            ?? EpochDate.decode(c, forKey: .createdAt)
        attributes = ((try? c.decodeIfPresent([BuysideAttribute].self, forKey: .buysideAttributes)) ?? nil)?
            .filter { $0 != .unknown } ?? []

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

    /// Who to show as the counterparty on this row. When the account is
    /// acting for a client — a banker's buyside client, or a fund's portfolio
    /// company — the client is the company, and the account moves to
    /// `companySubtitle`. Mirrors `constructCompanyNames`
    /// (axl-grid-company-info-cell-renderer.helpers.ts).
    var displayName: String {
        if actsForClient {
            if let name = demandClientName, !name.isEmpty { return name }
            return "Anonymous Company"
        }
        if let name = demandAccountName, !name.isEmpty { return name }
        if let name = demandUserName, !name.isEmpty { return name }
        return isAnonymous ? "Anonymous Buyer" : "Unnamed Member"
    }

    /// "client of …" / "Portfolio Co. of …", when the company is a client.
    var companySubtitle: String? {
        guard actsForClient, let account = demandAccountName, !account.isEmpty else { return nil }
        return demandClientIntentSubtype == "add_on" ? "Portfolio Co. of \(account)" : "client of \(account)"
    }

    private var actsForClient: Bool {
        demandClientIntentSubtype == "buyside" || demandClientIntentSubtype == "add_on"
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
    /// `referral.referral_source` — the accept growl words itself off it.
    var referralSource: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case supplyStatus = "supply_status"
        case demandIsRead = "demand_is_read"
        case referral
    }

    private enum ReferralKeys: String, CodingKey { case referralSource = "referral_source" }

    init(id: String, supplyStatus: DealStatus?, demandIsRead: Bool?, referralSource: String? = nil) {
        self.id = id
        self.supplyStatus = supplyStatus
        self.demandIsRead = demandIsRead
        self.referralSource = referralSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        supplyStatus = try c.decodeIfPresent(DealStatus.self, forKey: .supplyStatus)
        demandIsRead = try? c.decodeIfPresent(Bool.self, forKey: .demandIsRead)
        let referral = try? c.nestedContainer(keyedBy: ReferralKeys.self, forKey: .referral)
        referralSource = (try? referral?.decodeIfPresent(String.self, forKey: .referralSource)) ?? nil
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

// MARK: - Member card

extension SellsideDeal {
    /// `ACCOUNT_TYPES` (account-types.constants.ts), keyed by account code.
    static let accountTypeLabels: [String: String] = [
        "FO": "Family Office", "HC": "Holding Company", "PE": "Private Equity Fund",
        "PF": "Independent Sponsor", "VC": "Venture Capital", "MB": "Merchant Bank",
        "AF": "M&A Advisory Firm", "BB": "Business Broker", "IB": "Investment Bank",
        "HF": "Hedge Fund", "JC": "Junior/Mezz Lender", "SL": "Senior Lender",
        "A": "Accountant", "CO": "Consultant", "LF": "Law Firm", "C": "Corporation",
        "II": "Individual Accredited Investor", "SF": "Search Fund",
    ]

    /// The web's Company Type column: `ACCOUNT_TYPES[companyCode]`.
    var companyType: String? {
        companyCode.flatMap { Self.accountTypeLabels[$0] }
    }

    /// "Austin, TX" in the US and Canada, "London, GB" elsewhere; nil
    /// without a city. `tableData.location` in supply-deals-row.model.ts.
    var location: String? {
        guard let city = city?.trimmingCharacters(in: .whitespaces), !city.isEmpty else { return nil }
        let region = (country == "US" || country == "CA" ? stateProvince : country)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return region.isEmpty ? city : "\(city), \(region)"
    }

    /// "Jordan: Thanks, we'll take a look" — the web's last-message cell,
    /// which names the sender by a guessed first name.
    var lastMessagePreview: String? {
        guard let message = lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return nil }
        let firstName = lastMessageFromFullName?.split(separator: " ").first.map(String.init)
        return firstName.map { "\($0): \(message)" } ?? message
    }

    /// Unread messages, except that a lone empty message doesn't count — the
    /// web drops it the same way (`isEmptySingleMessage`).
    var unreadMessageCount: Int {
        newMessageCount == 1 && lastMessagePreview == nil ? 0 : newMessageCount
    }
}

/// A badge on a buyer. Mirrors the axial-api `BuysideAttributes` enum
/// (`TBuysideAttribute` in supply-deals-row.model.ts) plus `top_pick`, which
/// the web's tag table (`ROW_ITEM_TAGS`, sell.constants.ts) already handles.
enum BuysideAttribute: String, Decodable, Hashable {
    case axialCloser = "axial_closer"
    case closedDealsInYourSector = "closed_deals_in_your_sector"
    case highlyResponsiveBuyer = "highly_responsive_buyer"
    case portfolioCompany = "portfolio_company"
    case referral
    case inboundInquiry = "inbound_inquiry"
    case topPick = "top_pick"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BuysideAttribute(rawValue: raw) ?? .unknown
    }

    /// `ROW_ITEM_TAGS[…].value`.
    var label: String {
        switch self {
        case .axialCloser: "Axial Closer"
        case .closedDealsInYourSector: "Closed Deals in Your Sector"
        case .highlyResponsiveBuyer: "Highly Responsive Buyer"
        case .portfolioCompany: "Portfolio Company"
        case .referral: "Referral"
        case .inboundInquiry: "Inbound Inquiry"
        case .topPick: "Top Pick"
        case .unknown: ""
        }
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

    /// The short labels the breakdown chart uses (`CAPITAL_SOURCE_BUCKETS`).
    var label: String {
        switch self {
        case .committed: "Committed"
        case .dealByDeal: "Deal by Deal"
        case .balanceSheet: "Balance Sheet"
        case .personalWealth: "Personal Wealth"
        case .other, .unknown: "Other"
        }
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
