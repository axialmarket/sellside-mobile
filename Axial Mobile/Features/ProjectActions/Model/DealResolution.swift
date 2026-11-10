//
//  DealResolution.swift
//  Axial Mobile
//

import Foundation

/// The things a member can be waiting on the seller for — the web sidebar's
/// primary buttons (sell-sidebar.service.ts), and the deal-level half of the
/// dashboard's action items. Each card shows its own; the dashboard runs
/// them in bulk.
enum DealResolveAction: Hashable, Identifiable {
    /// An inquiry or referral asking for access.
    case accept
    case pass
    case reviewRedlines
    case shareCim

    var id: Self { self }

    /// What a card offers, in the sidebar's order (secondary first).
    static func offered(for deal: SellsideDeal) -> [DealResolveAction] {
        if deal.supplyStatus == .targetRequestedAccess { return [.pass, .accept] }
        if deal.showsNdaRedline { return [.reviewRedlines] }
        // The sidebar offers Send CIM from viewed-NDA on; the note sheet
        // drops anyone who isn't eligible yet.
        if [.targetViewedNda, .targetSignedNda, .markedNdaSigned].contains(deal.supplyStatus) {
            return [.shareCim]
        }
        return []
    }

    /// The sidebar's labels: "Accept Referral" for a buyside referral
    /// (`wasBuysideReferral`), otherwise "Accept Inquiry".
    func label(for deal: SellsideDeal) -> String {
        switch self {
        case .accept: deal.isActiveBuysideReferral ? "Accept Referral" : "Accept Inquiry"
        case .pass: "Pass on Member"
        case .reviewRedlines: "Review Redlines"
        case .shareCim: "Send CIM"
        }
    }

    var systemImage: String {
        switch self {
        case .accept: "checkmark"
        case .pass: "xmark"
        case .reviewRedlines: "doc.text.magnifyingglass"
        case .shareCim: "paperplane"
        }
    }

    var isPrimary: Bool { self != .pass }
}

/// One request to resolve something, from a card or the dashboard.
enum DealResolution: Identifiable, Equatable {
    case accept([SellsideDeal])
    case pass([SellsideDeal])
    case shareCim([SellsideDeal])
    case reviewRedlines(SellsideDeal)

    /// Matches `DealResolveAction`'s case names, so a card's button and the
    /// sheet it opens can share a zoom source id.
    var kind: String {
        switch self {
        case .accept: "accept"
        case .pass: "pass"
        case .shareCim: "shareCim"
        case .reviewRedlines: "reviewRedlines"
        }
    }

    var deals: [SellsideDeal] {
        switch self {
        case .accept(let deals), .pass(let deals), .shareCim(let deals): deals
        case .reviewRedlines(let deal): [deal]
        }
    }

    /// The zoom source of a card's button: "<deal id>.<action>".
    static func cardSourceID(dealId: String, action: DealResolveAction) -> String { "\(dealId).\(action)" }

    var cardSourceID: String { Self.cardSourceID(dealId: deals.first?.id ?? "", action: action) }

    private var action: DealResolveAction {
        switch self {
        case .accept: .accept
        case .pass: .pass
        case .shareCim: .shareCim
        case .reviewRedlines: .reviewRedlines
        }
    }

    var id: String {
        switch self {
        case .accept(let deals): "accept-" + deals.map(\.id).joined(separator: ",")
        case .pass(let deals): "pass-" + deals.map(\.id).joined(separator: ",")
        case .shareCim(let deals): "cim-" + deals.map(\.id).joined(separator: ",")
        case .reviewRedlines(let deal): "redline-\(deal.id)"
        }
    }
}

// MARK: - Accept

/// The bulk accept confirmation — `getBulkAcceptModalTexts`
/// (sell-intent.helpers.ts). Mixed beats referrals beats inquiries.
struct BulkAcceptCopy: Equatable {
    let title: String
    /// Markdown: the web bolds the middle clause.
    let message: String
    let confirm: String

    init(deals: [SellsideDeal]) {
        let n = deals.count
        let referrals = deals.filter(\.isActiveBuysideReferral).count
        let inquiries = deals.filter(\.isActiveInboundInquiry).count
        func plural(_ word: String) -> String {
            guard n != 1 else { return word }
            return word == "inquiry" ? "inquiries" : word + "s"
        }
        if referrals > 0, inquiries > 0 {
            title = "Accept Requests"
            message = "You're about to **accept \(n) \(plural("request")) and share the NDA**, would you like to proceed?"
            confirm = "Accept \(n) \(plural("request").capitalized)"
        } else if n > 0, referrals == n {
            title = "Accept Referrals"
            message = "You're about to **accept \(n) \(plural("referral")) and share the NDA**, would you like to proceed?"
            confirm = "Accept \(n) \(plural("referral").capitalized)"
        } else {
            title = "Accept Inquiries"
            message = "You're about to **accept the \(plural("inquiry")) of \(n) interested \(plural("member"))**, would you like to proceed?"
            confirm = "Accept \(n) \(plural("inquiry").capitalized)"
        }
    }

    /// The success growl, worded off the deals that came back.
    static func success(count: Int, referralSources: [String?]) -> String {
        let referred = referralSources.filter { $0 != nil }.count
        let term = referred > 0 && referred < referralSources.count ? "request"
            : referred == referralSources.count && referred > 0 ? "referral" : "inquiry"
        return "\(count) member\(count == 1 ? " has" : "s have") been notified of your \(term) acceptance."
    }
}

extension SellsideDeal {
    /// An access request with no referral behind it.
    var isActiveInboundInquiry: Bool {
        supplyStatus == .targetRequestedAccess && referralSource == nil
    }
}

// MARK: - Pass

/// `openPassOnMemberModal` (one) and the bulk pass modal (several).
struct PassCopy: Equatable {
    let title = "Pass on Member"
    let message: String
    let confirm: String

    init(deals: [SellsideDeal]) {
        if deals.count == 1, let deal = deals.first {
            let name = deal.demandAccountName ?? deal.displayName
            message = "You're about to **pass on \(name)** and remove them from your list, would you like to proceed? This cannot be undone."
            confirm = "Pass on Member"
        } else {
            let n = deals.count
            message = "You're about to **pass on \(n) member\(n == 1 ? "" : "s")**, would you like to proceed?"
            confirm = "Pass on \(n) Member\(n == 1 ? "" : "s")"
        }
    }

    static func success(count: Int) -> String {
        "Successfully passed on \(count) \(count == 1 ? "member" : "members")."
    }
}

// MARK: - CIM note

/// The Draft CIM Note sheet's rules — cim-note-sidebar.component.ts.
struct CIMNoteRecipients: Equatable {
    /// Who will get it.
    let eligible: [SellsideDeal]
    /// Access requests were in the selection — accept them first.
    let removedInquiries: Bool
    /// Never pursued, so not eligible.
    let removedNeverPursued: Int

    init(deals: [SellsideDeal]) {
        var eligible: [SellsideDeal] = []
        var inquiries = false
        var neverPursued = 0
        for deal in deals {
            if deal.supplyStatus == .targetRequestedAccess { inquiries = true }
            else if !deal.hasTargetPursued { neverPursued += 1 }
            else { eligible.append(deal) }
        }
        self.eligible = eligible
        removedInquiries = inquiries
        removedNeverPursued = neverPursued
    }

    var inquiriesNotice: String? {
        removedInquiries
            ? "Inbound inquiries need to be accepted before sending them the CIM. We've removed them from your selection - only the remaining members will receive the CIM."
            : nil
    }

    var ineligibleNotice: String? {
        let k = removedNeverPursued
        guard k > 0 else { return nil }
        return "\(k) member\(k > 1 ? "s are" : " is") not eligible to receive the CIM and will be removed from your selection."
    }

    /// "Share CIM with Jordan Reyes" / "Share CIM with 4 Members".
    var ctaLabel: String {
        if eligible.count == 1, let deal = eligible.first {
            return "Share CIM with \(deal.demandUserName ?? deal.displayName)"
        }
        return "Share CIM with \(eligible.count) Members"
    }

    static let defaultMessage = "{recipient[first_name]},\n\nThank you for signing the NDA. The CIM is now available for your review.\n\nPlease share your feedback at your earliest convenience. Feel free to reach out anytime with questions or to discuss next steps."

    /// The saved CIM note, else the default.
    static func message(from intent: JSONValue) -> String {
        intent["cim"]?["message"]?.text ?? defaultMessage
    }

    /// "CIM has been sent to Bluewater Capital." / "…to 4 members."
    static func success(_ eligible: [SellsideDeal]) -> String {
        if eligible.count == 1, let deal = eligible.first {
            return "CIM has been sent to \(deal.demandAccountName ?? deal.displayName)."
        }
        return "CIM has been sent to \(eligible.count) members."
    }

    /// The files the note goes out with — read-only, as on the web.
    static func files(from intent: JSONValue) -> [String] {
        if intent["cim_type"]?.string == "linked", let link = intent["linked_cim"]?.text { return [link] }
        return intent["documents"]?.array?
            .filter { $0["document_type"]?.string == "cim" || $0["type"]?.string == "OM" }
            .compactMap { $0["filename"]?.string } ?? []
    }
}

/// `POST /deals/send-cim`.
struct SendCIMRequest: Encodable, Equatable {
    let message: String
    let ccMembers: [String]
    let dealIds: [String]
    let subject: String

    enum CodingKeys: String, CodingKey {
        case message, subject
        case ccMembers = "cc_members"
        case dealIds = "deal_ids"
    }
}

/// `{ deal_ids }` — bulk approve and reject.
struct DealIDsRequest: Encodable, Equatable {
    let dealIds: [String]
    enum CodingKeys: String, CodingKey { case dealIds = "deal_ids" }
}

/// A member of the owning account — `GET /accounts/{id}/members`, for CC.
struct AccountMember: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
    }

    init(id: String, fullName: String) {
        self.id = id
        self.fullName = fullName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let first = (try? c.decodeIfPresent(String.self, forKey: .firstName)) ?? nil
        let last = (try? c.decodeIfPresent(String.self, forKey: .lastName)) ?? nil
        let joined = [first, last].compactMap { $0 }.joined(separator: " ")
        fullName = ((try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? nil) ?? (joined.isEmpty ? "Team member" : joined)
    }
}
