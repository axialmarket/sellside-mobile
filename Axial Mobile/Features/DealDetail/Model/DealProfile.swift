//
//  DealProfile.swift
//  Axial Mobile
//

import Foundation

/// The buyer behind one deal, as the web's sell sidebar shows it —
/// `GET /api/deals/sellside-sidebar/{dealId}` (`DealApiService
/// .fetchSellsideSidebarDeal`), an `ISellsideSidebarDealData`: the full
/// `IDealData` plus the buyer account's tombstones, industries, offices and
/// members.
///
/// Read out of a `JSONValue` rather than decoded field by field. The payload
/// nests the buyer three levels deep (`demand_intent.owned_by_account…`) and
/// almost all of it is optional; a missing branch should cost one line of the
/// profile, never the screen.
struct DealProfile: Equatable {
    struct Person: Equatable, Identifiable {
        let id: String
        let fullName: String
        let firstName: String?
        let title: String?
        let email: String?
        let linkedInURL: URL?
        let headshotURL: URL?
    }

    struct Office: Equatable, Identifiable {
        let id: String
        let isHeadquarters: Bool
        let street: [String]
        /// "New York, NY 10016" — `<axl-office>`.
        let locality: String
        let phone: String?
    }

    struct Client: Equatable {
        let name: String?
        /// `"direct" | "add_on" | "buyside"`.
        let intentSubtype: String?
        /// `"strategic" | "financial"`.
        let buysideType: String?
    }

    struct ClosedDeal: Equatable, Identifiable {
        let id: String
        let company: String
        let transactionDate: String?
    }

    /// `$X.YM` either side, as the sourcing criteria prints it.
    struct MoneyRange: Equatable {
        let min: Double?
        let max: Double?
    }

    let id: String
    let contact: Person?
    /// `buyside_responsiveness`, a percentage.
    let responsiveness: Int?
    let submittedBids: Int?
    /// `assigned_to_user_rating.average`.
    let rating: Double?

    let accountName: String?
    let accountDescription: String?
    let website: String?
    let accountJoined: Date?
    let hasActivePortcos: Bool
    let capitalSource: CapitalSource?
    /// `Account.primaryOfficeLocation`.
    let primaryOfficeLocation: String?

    let intentType: String?
    let intentSource: String?
    let intentDescription: String?
    let client: Client?

    let industries: [String]
    let team: [Person]
    let offices: [Office]
    let closedDeals: [ClosedDeal]

    let revenueRange: MoneyRange?
    let ebitdaRange: MoneyRange?
    let sourcingIndustries: [String]

    /// The note an inbound inquiry or referral came with —
    /// `request_access_event.extra_data.message`.
    let inquiryNote: String?
    let hasTargetPursued: Bool
    let isAnonymous: Bool
    /// `message_counts` — conversation that predates the feed, which the
    /// web links out to the old message center for.
    let hasLegacyMessages: Bool
    /// The buyer's account id, for the counterparty members a message
    /// can be addressed to.
    let accountId: String?

    // Who the feed names on the seller's side of the deal.
    /// `supplyIntent.assignedToUser.full_name`.
    let supplyMemberName: String?
    let supplyAccountName: String?
    /// `Deal.isBuysideReferral` — the referral came from the buyer.
    let isBuysideReferral: Bool
    /// A new message's subject when there's no thread to reply to — the
    /// buyer's intent headline, else the project's.
    let headline: String?

    // Read by the Files tab.
    /// `documents` — what's been shared on this deal.
    let documents: [JSONValue]
    /// `signed_nda`, kept even after the deal moves on.
    let signedNda: JSONValue?
    /// The project's CIM link, when it shares one instead of a file.
    let linkedCim: URL?
}

// MARK: - Reading

extension DealProfile {
    init(json deal: JSONValue) {
        let intent = deal["demand_intent"]
        let account = intent?["owned_by_account"]
        let user = intent?["assigned_to_user"]

        id = deal["public_id"]?.string ?? deal["id"]?.string ?? ""
        contact = user.flatMap(Person.init(json:))
        let metrics = Self.metrics(user?["passport_metrics"])
        responsiveness = metrics["buyside_responsiveness"].map { Int($0.rounded()) }
        submittedBids = metrics["buyside_submitted_bids"].map { Int($0) }
        rating = intent?["assigned_to_user_rating"]?["average"]?.number

        accountName = account?["name"]?.text
        accountDescription = account?["description"]?.text.map(PlainText.from(html:))
        website = account?["website"]?.text
        accountJoined = account?["date_joined"]?.date
        hasActivePortcos = account?["has_active_portcos"]?.bool ?? false
        capitalSource = account?["capital_source"]?.string.flatMap(CapitalSource.init(rawValue:))
        primaryOfficeLocation = account?["primary_office"].flatMap(Self.location(of:))

        intentType = intent?["intent_type"]?.string
        intentSource = intent?["intent_source"]?.string
        intentDescription = intent?["description"]?.text.map(PlainText.from(html:))
        client = intent?["client"].flatMap { client in
            client.object == nil ? nil : Client(name: client["client_name"]?.text,
                                                intentSubtype: client["intent_subtype"]?.string,
                                                buysideType: client["buyside_type"]?.string)
        }

        industries = Self.unique(deal["demand_account_industries"]?.array?.compactMap { $0["name"]?.text } ?? [])
        let contactId = contact?.id
        team = (deal["demand_account_members"]?.array ?? [])
            .filter { $0["is_active"]?.bool != false }
            .sorted { ($0["order_sequence"]?.number ?? .infinity) < ($1["order_sequence"]?.number ?? .infinity) }
            .compactMap(Person.init(json:))
            .filter { $0.id != contactId }
        // HQ first — `sortedDemandOffices`.
        offices = (deal["demand_account_offices"]?.array ?? []).enumerated()
            .compactMap { Office(json: $0.element, index: $0.offset) }
            .sorted { $0.isHeadquarters && !$1.isHeadquarters }
        closedDeals = (deal["demand_account_tombstones"]?.array ?? []).enumerated().compactMap { index, tombstone in
            guard let company = tombstone["sellside_company_name"]?.text else { return nil }
            return ClosedDeal(id: tombstone["public_id"]?.string ?? "\(index)", company: company,
                              transactionDate: tombstone["transaction_date"]?.text)
        }

        let financials = deal[path: "reasons.financial.buyer.financials"]
        revenueRange = Self.range(financials?["revenue"]?["range"])
        ebitdaRange = Self.range(financials?["ebitda"]?["range"])
        // An implied match names the seller's industry, a direct one the
        // buyer's — the sourcing criteria's `industries` mapping.
        sourcingIndustries = Self.unique((deal[path: "reasons.industry.matches"]?.array ?? []).compactMap { match in
            let side = match["is_implied_match"]?.bool == true ? "seller" : "buyer"
            return match[side]?["industry"]?["name"]?.text
        })

        inquiryNote = deal[path: "request_access_event.extra_data.message"]?.text
        hasTargetPursued = deal["has_target_pursued"]?.bool ?? false
        isAnonymous = deal["is_anonymous"]?.bool ?? false
        let counts = deal["message_counts"]?.object ?? [:]
        hasLegacyMessages = counts.values.contains { ($0.number ?? 0) > 0 }
        accountId = account?["public_id"]?.string ?? account?["id"]?.string

        let supply = deal["supply_intent"]
        supplyMemberName = supply?["assigned_to_user"].flatMap(Person.init(json:))?.fullName
        supplyAccountName = supply?["owned_by_account"]?["name"]?.text
        let referral = deal[path: "referral.referral_source"]?.string
        isBuysideReferral = referral == "deal" || referral == "teaser"
        headline = intent?["headline"]?.text ?? supply?["headline"]?.text

        documents = deal["documents"]?.array ?? []
        signedNda = deal["signed_nda"].flatMap { $0.object == nil ? nil : $0 }
        linkedCim = supply?["cim_type"]?.string == "linked"
            ? supply?["linked_cim"]?.text.flatMap(DealProfile.webURL) : nil
    }

    private static func metrics(_ json: JSONValue?) -> [String: Double] {
        var metrics: [String: Double] = [:]
        for metric in json?.array ?? [] {
            if let name = metric["name"]?.string, let value = metric["value"]?.number { metrics[name] = value }
        }
        return metrics
    }

    private static func range(_ json: JSONValue?) -> MoneyRange? {
        let range = MoneyRange(min: json?["min_value"]?.number, max: json?["max_value"]?.number)
        return range.min == nil && range.max == nil ? nil : range
    }

    /// "City, Region" in the US and Canada, "City, Country" elsewhere.
    static func location(of office: JSONValue) -> String? {
        guard let city = office["city"]?.text else { return nil }
        let country = office["country"]?.text
        let region = country == "US" || country == "CA" ? office["region"]?.text : country
        return region.map { "\(city), \($0)" } ?? city
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

extension DealProfile.Person {
    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        let first = json["first_name"]?.text
        let last = json["last_name"]?.text
        let joined = [first, last].compactMap { $0 }.joined(separator: " ")
        let name = json["full_name"]?.text ?? (joined.isEmpty ? nil : joined) ?? json["anonymous_full_name"]?.text
        id = json["id"]?.string ?? json["public_id"]?.string ?? name ?? UUID().uuidString
        fullName = name ?? "Axial Member"
        firstName = first
        title = json["title"]?.text
        email = json["email"]?.text
        linkedInURL = json["linkedin_url"]?.text.flatMap(DealProfile.webURL)
        // `headshot` is a picture object on a user and a bare URL on a
        // nested member (`INestedMemberData`).
        headshotURL = (json["headshot"]?["thumb_url"]?.text ?? json["headshot"]?.text).flatMap(URL.init(string:))
    }
}

extension DealProfile.Office {
    init?(json: JSONValue, index: Int) {
        guard json.object != nil else { return nil }
        id = json["public_id"]?.string ?? "\(index)"
        isHeadquarters = json["type_code"]?.string == "HQ"
        let street = json["street_address"]
        self.street = street?.array != nil ? street?.strings.filter { !$0.isEmpty } ?? [] : street?.text.map { [$0] } ?? []
        let cityRegion = [json["city"]?.text, json["region"]?.text].compactMap { $0 }.joined(separator: ", ")
        locality = [cityRegion, json["postal_code"]?.text ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        phone = json["phone"]?["number"]?.text
    }
}

// MARK: - What the profile says

extension DealProfile {
    /// The sidebar header's title — "Jordan Reyes at Bluewater Capital".
    var headerTitle: String? {
        switch (contact?.fullName, accountName) {
        case let (person?, account?): "\(person) at \(account)"
        case let (person?, nil): person
        case let (nil, account?): account
        default: nil
        }
    }

    /// "3 Years on Axial" — `Account.age`, which compares calendar years,
    /// not elapsed time.
    func accountAge(now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let accountJoined else { return nil }
        let years = calendar.component(.year, from: now) - calendar.component(.year, from: accountJoined)
        return years > 1 ? "\(years) Years on Axial" : years == 1 ? "1 Year on Axial" : "<1 Year on Axial"
    }

    /// `investingOnBehalfOf` in sell-sidebar-overview.component.ts.
    var investingOnBehalfOf: String? {
        guard intentType == "buy_business", let client else { return nil }
        switch client.intentSubtype {
        case "add_on":
            return "Making strategic acquisitions on behalf of \(client.name ?? "a portfolio company")"
        case "buyside" where client.buysideType == "strategic":
            return "Making strategic acquisitions on behalf of \(client.name ?? "a client")"
        case "buyside":
            return "Making acquisitions on behalf of \(client.name ?? "a financial sponsor")"
        default:
            return nil
        }
    }

    /// "Has committed capital" — `sellPanelCapSourceLabels`.
    var capitalSourceLine: String? {
        let label: String? = switch capitalSource {
        case .committed: "committed capital"
        case .dealByDeal: "deal-by-deal financing"
        case .balanceSheet: "balance sheet financing"
        case .personalWealth: "personal or family wealth"
        case .other: "other financing"
        case .unknown, nil: nil
        }
        return label.map { "Has \($0)" }
    }

    /// "4 closed deals" — the overview's first line. The web adds ", N in
    /// your sector"; that count needs the project's sectors matched against
    /// each tombstone, which mobile leaves to the badge of the same name.
    var closedDealsLine: String? {
        closedDeals.isEmpty ? nil : "\(closedDeals.count) closed deal\(closedDeals.count == 1 ? "" : "s")"
    }

    /// The About text. A portfolio company's own description comes first,
    /// then its sponsor's — the web joins them with a rule.
    var about: String? {
        let parts = intentType == "buy_business" && client?.intentSubtype == "add_on"
            ? [intentDescription, accountDescription]
            : [accountDescription]
        let text = parts.compactMap { $0 }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    /// `displayedOverviewSections`, less the contact's LinkedIn, which
    /// mobile shows on the Primary Contact card only.
    var hasOverview: Bool {
        closedDealsLine != nil || hasActivePortcos || investingOnBehalfOf != nil || capitalSourceLine != nil
            || website != nil || about != nil
    }

    /// Hidden for a deal that came in through a referral, which has no
    /// sourcing behind it.
    var showsSourcingCriteria: Bool {
        intentSource != "deal_referral" && (revenueRange != nil || ebitdaRange != nil || !sourcingIndustries.isEmpty)
    }

    /// `MillionsFormatterPipe` on a raw dollar amount: `$12.5M`, `$0`.
    static func millions(_ amount: Double) -> String {
        guard amount != 0 else { return "$0" }
        return "$" + (amount / 1_000_000).formatted(.number.precision(.fractionLength(1)).grouping(.never)) + "M"
    }

    static func webURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }
}

extension DealProfile.MoneyRange {
    /// "$5.0M – $50.0M". The web prints "null" for a missing end; an open
    /// end reads better as "+" or "up to".
    var formatted: String {
        switch (min, max) {
        case let (min?, max?): "\(DealProfile.millions(min)) – \(DealProfile.millions(max))"
        case let (min?, nil): "\(DealProfile.millions(min))+"
        case let (nil, max?): "Up to \(DealProfile.millions(max))"
        default: ""
        }
    }
}

// MARK: - Plain text

/// The API stores descriptions and message bodies as HTML. Mobile shows them
/// as plain text, converted once on the model — never per render, and never
/// through `NSAttributedString`'s HTML importer, which runs WebKit on the
/// main thread.
enum PlainText {
    static func from(html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }
        var text = html
        for pattern in ["<br\\s*/?>", "</p>", "</div>", "</li>", "<hr\\s*/?>"] {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                        "&#39;": "'", "&apos;": "'", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
                        "&rdquo;": "\u{201D}", "&ldquo;": "\u{201C}", "&mdash;": "\u{2014}", "&ndash;": "\u{2013}"]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The reverse, for a message going out: paragraphs, escaped.
    static func html(from text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let escaped = line.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<p>\(escaped.isEmpty ? "<br/>" : escaped)</p>"
        }.joined()
    }
}

extension JSONValue {
    /// Epoch milliseconds or an ISO 8601 string — see `EpochDate`.
    var date: Date? {
        switch self {
        case .number(let milliseconds):
            milliseconds > 0 ? Date(timeIntervalSince1970: milliseconds / 1000) : nil
        case .string(let text):
            EpochDate.iso8601(text) ?? Double(text).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        default:
            nil
        }
    }
}
