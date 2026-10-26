//
//  OutreachForms.swift
//  Axial Mobile
//

import Foundation

/// `SharingSetting` (sharing-setting.utils.ts).
enum SharingSetting: Equatable {
    case smartshare, manual, inboundInquiry

    /// `sharingSettingFromApiValues`.
    init(useSmartshare: Bool, requiresApproval: Bool, canManuallyShare: Bool) {
        if canManuallyShare, useSmartshare, requiresApproval { self = .inboundInquiry }
        else if useSmartshare { self = .smartshare }
        else { self = .manual }
    }

    init(intent: JSONValue) {
        self.init(useSmartshare: intent["use_smartshare"]?.bool ?? false,
                  requiresApproval: intent["requires_approval"]?.bool ?? false,
                  canManuallyShare: intent["owned_by_account"]?["can_manually_share"]?.bool ?? true)
    }
}

/// A member of the owning account — `GET /accounts/{id}/members`.
struct AccountMember: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let fullName: String
    let isTosSigned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case isTosSigned = "is_tos_signed"
    }

    /// Ids arrive with and without hyphens depending on the endpoint.
    func matches(_ other: String?) -> Bool {
        other.map { IntentID.normalized($0) == IntentID.normalized(id) } ?? false
    }

    init(id: String, fullName: String, isTosSigned: Bool = true) {
        self.id = id
        self.fullName = fullName
        self.isTosSigned = isTosSigned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "Team member"
        isTosSigned = (try? c.decodeIfPresent(Bool.self, forKey: .isTosSigned)) ?? true
    }
}

// MARK: - Sharing Settings

/// The Sharing Settings step — sharing-settings.service.ts and
/// `extractSharingSettingsFromForm`.
struct SharingSettingsForm: Equatable {
    var sharingMode: String
    var requiresApproval: Bool
    var companyTypes: [String]
    var capitalSources: [String]
    var acquirerType: String?
    var minimumClosedDeals: String?
    var geography: [Int]?
    var blockedCounterparties: [String]
    var canHaveReferralLinks: String
    /// `effectiveCanManuallyShare`: the account flag, or a grandfathered
    /// Manual intent.
    let canManuallyShare: Bool
    /// Kept so `created_at`/`updated_at` inside it don't read as changes.
    private let existingFilters: JSONValue

    init(intent: JSONValue) {
        let accountFlag = intent["owned_by_account"]?["can_manually_share"]?.bool ?? true
        let useSmartshare = intent["use_smartshare"]?.bool ?? false
        let requires = intent["requires_approval"]?.bool
        let grandfathered = !accountFlag && !useSmartshare && requires == false
        canManuallyShare = accountFlag || grandfathered

        if !canManuallyShare {
            sharingMode = "smartshare"
            requiresApproval = requires ?? true
        } else {
            switch SharingSetting(useSmartshare: useSmartshare, requiresApproval: requires ?? false,
                                  canManuallyShare: accountFlag) {
            case .smartshare: sharingMode = "smartshare"; requiresApproval = false
            case .inboundInquiry: sharingMode = "manual"; requiresApproval = true
            case .manual: sharingMode = "manual"; requiresApproval = false
            }
        }

        let filters = intent["advanced_filters"] ?? .object([:])
        existingFilters = filters
        let accountTypes = filters["account_type"]?.strings ?? []
        companyTypes = accountTypes.count >= OutreachOptions.companyTypes.count ? [] : accountTypes
        let sources = filters["capital_source"]?.strings ?? []
        capitalSources = sources.count >= OutreachOptions.capitalSources.count ? [] : sources
        let acquirer = filters["acquirer_type"]?.strings.first ?? filters["acquirer_type"]?.string
        acquirerType = ["strategic", "financial"].contains(acquirer ?? "") ? acquirer : nil
        let minimum = filters["min_closed_deals"]?.int.map(String.init) ?? "0"
        minimumClosedDeals = ["1", "3", "5"].contains(minimum) ? minimum : nil
        let geo = filters["geography"]?.array?.compactMap(\.int) ?? []
        geography = geo.isEmpty ? nil : geo
        blockedCounterparties = intent["supply_blocked_counterparties"]?.strings ?? []
        canHaveReferralLinks = intent["can_have_referral_links"]?.bool == true ? "yes" : "no"
    }

    /// Picking Manual sets Inbound Inquiry on; SmartShare sets it off.
    mutating func setSharingMode(_ mode: String) {
        guard mode != sharingMode else { return }
        sharingMode = mode
        requiresApproval = mode == "manual"
    }

    var advancedFilters: JSONValue {
        var filters = existingFilters.object ?? [:]
        filters["capital_source"] = .strings(capitalSources.count >= OutreachOptions.capitalSources.count ? [] : capitalSources)
        filters["account_type"] = .strings(companyTypes.count >= OutreachOptions.companyTypes.count ? [] : companyTypes)
        filters["acquirer_type"] = .strings(acquirerType.map { [$0] } ?? [])
        filters["min_closed_deals"] = .number(Double(Int(minimumClosedDeals ?? "0") ?? 0))
        filters["geography"] = .array((geography ?? []).map { .number(Double($0)) })
        return .object(filters)
    }

    func write(into intent: inout JSONValue) {
        intent.set(.bool(canHaveReferralLinks == "yes"), at: "can_have_referral_links")
        intent.set(.bool(sharingMode == "smartshare" || requiresApproval), at: "use_smartshare")
        intent.set(.bool(requiresApproval), at: "requires_approval")
        var seen: Set<String> = []
        let blocked = blockedCounterparties
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { Counterparty.validationError(for: $0) == nil && seen.insert($0).inserted }
        intent.set(.strings(blocked), at: "supply_blocked_counterparties")
        intent.set(advancedFilters, at: "advanced_filters")
    }

    var setting: SharingSetting {
        SharingSetting(useSmartshare: sharingMode == "smartshare" || requiresApproval,
                       requiresApproval: requiresApproval, canManuallyShare: canManuallyShare)
    }

    /// `buildPreferenceLabels`.
    var preferenceLabels: [String] {
        var labels: [String] = []
        if companyTypes.count == OutreachOptions.companyTypes.count {
            labels.append("Company Type: All Company Types")
        } else {
            labels += OutreachOptions.companyTypes.filter { companyTypes.contains($0.value) }.map { "Company Type: \($0.label)" }
        }
        if capitalSources.count == OutreachOptions.capitalSources.count {
            labels.append("Capital Source: All Capital Sources")
        } else {
            labels += OutreachOptions.capitalSources.filter { capitalSources.contains($0.value) }.map { "Capital Source: \($0.label)" }
        }
        if let acquirerType, let label = OutreachOptions.acquirerTypes.first(where: { $0.value == acquirerType })?.label {
            labels.append("Acquirer Type: \(label)")
        }
        if let minimumClosedDeals,
           let label = OutreachOptions.minimumClosedDeals.first(where: { $0.value == minimumClosedDeals })?.label {
            labels.append("Minimum Closed Deals: \(label)")
        }
        labels += (geography ?? []).map { "Location: \(Geography.label(forID: $0))" }
        return labels
    }

    var hasPreferences: Bool { !preferenceLabels.isEmpty }

    mutating func resetPreferences() {
        companyTypes = []; capitalSources = []; acquirerType = nil; minimumClosedDeals = nil; geography = nil
    }

    enum Field {
        static let blocked: SetupFieldKey = "sharingSettings.supplyBlockedCounterparties"
    }

    func validate(into v: inout StepValidationBuilder) {
        let errors = Set(blockedCounterparties.compactMap(Counterparty.validationError(for:)))
        v.check(Field.blocked, error: errors.isEmpty ? nil : errors.sorted().joined(separator: "\n"))
    }
}

/// `validateBlockedCounterparty` (counterparty.helpers.ts).
enum Counterparty {
    static let freeProviders: Set<String> = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "aol.com",
                                             "icloud.com", "me.com", "mac.com", "mail.com", "protonmail.com", "proton.me"]
    private static let label = "(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?"
    private static let domain = "@?" + label
    private static let url = "https?://" + label + "(?:/[^\\s]*)?"
    private static let email = "[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@" + label

    static func validationError(for raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let pattern = "^(\(email)|\(domain)|\(url))$"
        guard value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return "Enter a valid email address, email domain (e.g. @axial.com), or website"
        }
        let isEmail = value.range(of: "^\(email)$", options: [.regularExpression, .caseInsensitive]) != nil
        if !isEmail, let host = host(of: value), freeProviders.contains(host) {
            return "Public email domains (like Gmail, Yahoo) cannot be suppressed. Please enter a private business domain."
        }
        return nil
    }

    private static func host(of value: String) -> String? {
        var text = value.lowercased()
        if text.hasPrefix("http") { text = URL(string: text)?.host ?? text }
        if text.hasPrefix("@") { text.removeFirst() }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return text
    }

    /// The chips input: split a paste on commas and newlines, trim, drop
    /// blanks and duplicates.
    static func entries(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

enum OutreachOptions {
    static let companyTypes: [SetupChoice<String>] = [
        .init(value: "C", label: "Corporation"),
        .init(value: "HC", label: "Holding Company"),
        .init(value: "PE", label: "Private Equity Fund"),
        .init(value: "PF", label: "Independent Sponsor"),
        .init(value: "FO", label: "Family Office"),
        .init(value: "SF", label: "Search Fund"),
        .init(value: "II", label: "Individual Accredited Investor"),
        .init(value: "JC", label: "Junior/Mezz Lender"),
        .init(value: "SL", label: "Senior Lender"),
    ]

    static let capitalSources: [SetupChoice<String>] = [
        .init(value: "committed", label: "Committed"),
        .init(value: "deal_by_deal", label: "Deal by Deal"),
        .init(value: "balance_sheet", label: "Balance Sheet"),
        .init(value: "personal_wealth", label: "Personal Wealth"),
        .init(value: "other", label: "Other"),
    ]

    static let acquirerTypes: [SetupChoice<String>] = [
        .init(value: "", label: "All Acquirer Types"),
        .init(value: "strategic", label: "Strategic"),
        .init(value: "financial", label: "Financial"),
    ]

    static let minimumClosedDeals: [SetupChoice<String>] = [
        .init(value: "0", label: "Any Amount"),
        .init(value: "1", label: "At least 1"),
        .init(value: "3", label: "At least 3"),
        .init(value: "5", label: "At least 5"),
    ]

    static let referral: [SetupChoice<String>] = [
        .init(value: "yes", label: "Yes"),
        .init(value: "no", label: "No"),
    ]

    /// `SHARING_MODE_OPTIONS`.
    static let sharingModes: [SetupChoice<String>] = [
        .init(value: "smartshare",
              label: "SmartShare",
              detail: "An anonymized teaser is automatically shared to relevant members\nTailor which members are targeted using the settings above\nDiscoverable across Axial's online sites, while preserving anonymity",
              systemImage: "bolt.fill"),
        .init(value: "manual",
              label: "Manual Review",
              detail: "Review members one-by-one on your own\nTailor which members are recommended using the settings above",
              systemImage: "checklist"),
    ]

    static let inboundInquiryTooltip = "Members that you don't proactively contact will still be able to view your anonymized teaser. When a member pursues your anonymized teaser, your identity, custom teaser, and NDA are not shared. You will need to approve them before Axial shares further details."

    /// `nudge_days` choices, 3–20.
    static let followUpDays: [SetupChoice<String>] = (3...20).map { .init(value: String($0), label: String($0)) }
}

// MARK: - Marketing Settings

/// The Marketing Settings step (`messaging`) — marketing-settings.service.ts
/// and `extractMessagingFromForm`.
struct MessagingForm: Equatable {
    var assignedToUser: String?
    var additionalContacts: [String]
    var teaserCc: [String]
    var teaserMessage: String
    var followUpEnabled: Bool
    var followUpMessage: String
    var followUpDays: String

    static let teaserDefault = "{recipient[first_name]},\n\nBased on your criteria, you might be interested in looking at this opportunity. Have a look below for more details and next steps.\n\n"
    static let followUpDefault = "{recipient[first_name]},\n\nI'm following up on the recent deal I shared with you. If you are interested in learning more, please indicate your interest to move forward."

    init(intent: JSONValue) {
        assignedToUser = intent["assigned_to_user_public_id"]?.text
        additionalContacts = intent["extra_contacts"]?.strings ?? []
        let teaser = intent["teaser"]
        teaserCc = (teaser?["cc_emails"]?.strings ?? []) + (teaser?["cc_members"]?.strings ?? [])
        teaserMessage = (teaser?["message"]?.text ?? Self.teaserDefault).trimmingCharacters(in: .whitespacesAndNewlines)
        let followUp = intent["follow_up"]?["message"]?.text
        followUpEnabled = followUp != nil
        followUpMessage = followUp ?? Self.followUpDefault
        followUpDays = String(intent["nudge_days"]?.int ?? 3)
    }

    /// The primary contact can't also be an additional contact.
    mutating func setPrimaryContact(_ id: String?) {
        assignedToUser = id
        if let id { additionalContacts.removeAll { IntentID.normalized($0) == IntentID.normalized(id) } }
    }

    func write(into intent: inout JSONValue) {
        intent.set(.strings(additionalContacts), at: "extra_contacts")
        intent.set(.string(orNull: assignedToUser), at: "assigned_to_user_public_id")
        intent.set(.string(orNull: teaserMessage.isEmpty ? nil : teaserMessage), at: "teaser.message")
        // Non-member entries would go to cc_emails, which the web never
        // writes — the original stays. Mirrored.
        intent.set(.strings(teaserCc.filter(MemberID.isMemberID)), at: "teaser.cc_members")
        if followUpEnabled {
            intent.set(.string(orNull: followUpMessage.isEmpty ? nil : followUpMessage), at: "follow_up.message")
            intent.set(.number(orNull: Double(followUpDays)), at: "nudge_days")
        } else {
            intent.set(.null, at: "follow_up.message")
            intent.set(.null, at: "nudge_days")
        }
    }

    enum Field {
        static let assignedToUser: SetupFieldKey = "messaging.assigned_to_user"
    }

    func validate(memberCount: Int, into v: inout StepValidationBuilder) {
        if memberCount > 0 {
            v.require(Field.assignedToUser, satisfied: assignedToUser != nil, error: "")
        }
    }
}

/// Merge tags (`TEASER_TOKENS`). Only the first has an insert button.
enum MergeTag {
    static let recipientFirstName = "{recipient[first_name]}"
    static let all: [(token: String, label: String)] = [
        ("{recipient[first_name]}", "Recipient's First Name"),
        ("{assigned_to[full_name]}", "Primary Contact's Name"),
        ("{company[name]}", "Company Name"),
    ]
}
