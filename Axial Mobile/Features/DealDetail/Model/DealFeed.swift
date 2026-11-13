//
//  DealFeed.swift
//  Axial Mobile
//

import Foundation

/// One line of a deal's Messages tab. The web's `axl-messages-feed` merges
/// three sources into one timeline (`sortFeed`, messages-feed-content
/// .component.ts): thread messages, deal interactions (status history and
/// events), and internal comments. Mobile does the same here, once, so the
/// view only lays out what it's handed.
struct DealFeedItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case message(DealMessage)
        /// A status change or event, worded as the web words it. `detail` is
        /// the note an event carried (a CIM note, a follow-up, an inquiry).
        case activity(text: String, detail: String?)
        /// "{author} added an internal comment." — the note itself lives on
        /// the Comments tab.
        case comment(author: String)
    }

    let id: String
    let date: Date
    let kind: Kind
}

/// One message from a thread's `digest` — `IMessageData`.
struct DealMessage: Equatable, Identifiable {
    struct Recipient: Equatable, Hashable {
        let userId: String?
        let name: String?
        let email: String

        var displayName: String { name?.isEmpty == false ? name! : email }
    }

    /// `IMessageAttachmentData`.
    struct Attachment: Equatable, Hashable, Identifiable {
        let id: String
        let filename: String
        /// An image embedded in the body (`content_disposition: "inline"`),
        /// which the web leaves off its files list.
        let isInline: Bool
    }

    let id: String
    let from: Recipient
    let to: [Recipient]
    let cc: [Recipient]
    let subject: String?
    /// Plain text, converted from the HTML body once.
    let body: String
    let sentAt: Date
    /// No `read_at` on the viewer's copy. The web expands these.
    let isUnread: Bool
    let attachments: [Attachment]
    /// `"share_teaser" | "activity_report" | "user_message"`.
    let type: String?
}

// MARK: - Sources

/// The raw inputs, kept apart so a reply or a new comment can refresh one
/// without refetching the rest.
struct DealFeedSources: Equatable {
    var messages: [DealMessage] = []
    var interactions: [DealInteraction] = []
    var notes: [DealNote] = []
    /// `GET /users?ids=` — names for the user ids on each event, which the
    /// interactions endpoint sends bare.
    var userNames: [String: String] = [:]
}

/// `IContactHistoryData | IDealEventData` from `GET /deals/{id}/interaction`.
enum DealInteraction: Equatable {
    case history(StatusHistory)
    case event(Event)

    struct StatusHistory: Equatable {
        let source: String?
        let supplyStatus: String?
        let demandIsRead: Bool
        let oldDemandIsRead: Bool
        let actorName: String?
        let message: String?
        let date: Date
    }

    struct Event: Equatable {
        let id: String
        let type: String
        let sourceUserId: String?
        let targetUserId: String?
        let sourceUserName: String?
        let targetUserName: String?
        let fileName: String?
        let link: String?
        let message: String?
        let date: Date
    }

    init?(json: JSONValue) {
        if let type = json["event_type"]?.string {
            let extra = json["extra_data"]
            self = .event(Event(
                id: json["id"]?.string ?? UUID().uuidString,
                type: type,
                sourceUserId: json["source_user_id"]?.string,
                targetUserId: json["target_user_id"]?.string,
                sourceUserName: json["source_user"].flatMap(DealProfile.Person.init(json:))?.fullName,
                targetUserName: json["target_user"].flatMap(DealProfile.Person.init(json:))?.fullName,
                fileName: extra?["file_name"]?.text,
                link: extra?["cim_link"]?.text,
                message: extra?["message"]?.text.map(PlainText.from(html:)),
                date: json["created_at"]?.date ?? .distantPast
            ))
        } else if json.object != nil {
            self = .history(StatusHistory(
                source: json["source"]?.string,
                supplyStatus: json["supply_status"]?.string,
                demandIsRead: json["demand_is_read"]?.bool ?? false,
                oldDemandIsRead: json["old_demand_is_read"]?.bool ?? false,
                actorName: json["actor"].flatMap(DealProfile.Person.init(json:))?.fullName,
                message: json[path: "extra_data.message"]?.text.map(PlainText.from(html:)),
                date: json["created_at"]?.date ?? .distantPast
            ))
        } else {
            return nil
        }
    }

    var userIds: [String] {
        guard case .event(let event) = self else { return [] }
        return [event.sourceUserId, event.targetUserId].compactMap { $0 }
    }
}

extension DealMessage {
    /// Every message across a deal's threads. A user's inbox and sent
    /// copies of one thread carry the same messages, so they're deduped.
    static func messages(fromThreads threads: JSONValue) -> [DealMessage] {
        var seen = Set<String>()
        return (threads.array ?? []).flatMap { thread in
            (thread["digest"]?.array ?? []).compactMap(DealMessage.init(json:))
        }
        .filter { seen.insert($0.id).inserted }
    }

    init?(json: JSONValue) {
        guard let id = json["id"]?.string, let from = json["from_user"].flatMap(Recipient.init(json:)) else {
            return nil
        }
        self.id = id
        self.from = from
        to = json[path: "recipients.to"]?.array?.compactMap(Recipient.init(json:)) ?? []
        cc = json[path: "recipients.cc"]?.array?.compactMap(Recipient.init(json:)) ?? []
        subject = json["subject"]?.text
        body = PlainText.from(html: json["trimmed_body"]?.text ?? json["body"]?.text ?? "")
        sentAt = json["created_at"]?.date ?? .distantPast
        isUnread = json["read_at"].map { $0.isNull } ?? true
        attachments = json["attachments"]?.array?.compactMap { attachment in
            guard let id = attachment["public_id"]?.string ?? attachment["id"]?.string else { return nil }
            return Attachment(id: id, filename: attachment["user_filename"]?.text ?? "Attachment",
                              isInline: attachment["content_disposition"]?.string == "inline")
        } ?? []
        type = json["message_type"]?.string
    }
}

extension DealMessage.Recipient {
    init?(json: JSONValue) {
        guard let email = json["email"]?.text else { return nil }
        userId = json["user_id"]?.string
        name = json["name"]?.text
        self.email = email
    }
}

// MARK: - Wording

/// Who the feed names. `MessagesFeedHistoryComponent`'s getters, resolved
/// up front: the seller's member and account, the buyer's person and
/// company.
struct DealFeedNames: Equatable {
    var supplyMember: String
    var supplyAccount: String
    var demandPerson: String
    var demandCompany: String
    var isAnonymous = false
    var isBuysideReferral = false

    init(profile: DealProfile?, deal: SellsideDeal?) {
        supplyMember = profile?.supplyMemberName ?? "Your team"
        supplyAccount = profile?.supplyAccountName ?? "Your team"
        demandPerson = profile?.contact?.fullName ?? deal?.demandUserName ?? "The member"
        demandCompany = profile?.accountName ?? deal?.demandAccountName ?? deal?.displayName ?? "The member"
        isAnonymous = profile?.isAnonymous ?? deal?.isAnonymous ?? false
        isBuysideReferral = profile?.isBuysideReferral ?? false
    }

    init(supplyMember: String, supplyAccount: String, demandPerson: String, demandCompany: String,
         isAnonymous: Bool = false, isBuysideReferral: Bool = false) {
        self.supplyMember = supplyMember
        self.supplyAccount = supplyAccount
        self.demandPerson = demandPerson
        self.demandCompany = demandCompany
        self.isAnonymous = isAnonymous
        self.isBuysideReferral = isBuysideReferral
    }
}

extension DealFeedItem {
    /// The merged timeline, oldest first — the web reads top to bottom and
    /// scrolls to the end. Interactions the web doesn't render (a viewed
    /// CIM, which shows as the download event instead) are dropped.
    static func feed(from sources: DealFeedSources, names: DealFeedNames) -> [DealFeedItem] {
        var items = sources.messages.map { DealFeedItem(id: "m.\($0.id)", date: $0.sentAt, kind: .message($0)) }
        for (index, interaction) in sources.interactions.enumerated() {
            guard let (text, detail, date) = wording(for: interaction, names: names, users: sources.userNames) else {
                continue
            }
            // Status history has no id of its own — the web keys it on
            // position and time too.
            items.append(DealFeedItem(id: "i.\(index).\(date.timeIntervalSince1970)", date: date,
                                      kind: .activity(text: text, detail: detail)))
        }
        items += sources.notes.map {
            DealFeedItem(id: "n.\($0.id)", date: $0.createdAt, kind: .comment(author: $0.authorName))
        }
        return items.sorted { $0.date < $1.date }
    }

    /// `hasContactHistoryKey` / `hasEventKey` and the copy in
    /// messages-feed-history.component.html and messages-feed-event
    /// .component.html, supply side only.
    static func wording(for interaction: DealInteraction, names: DealFeedNames,
                        users: [String: String]) -> (String, String?, Date)? {
        switch interaction {
        case .history(let history):
            if history.source == "demand" {
                guard history.demandIsRead, !history.oldDemandIsRead else { return nil }
                return ("\(names.demandCompany) opened the teaser.", nil, history.date)
            }
            guard history.source == "supply", let raw = history.supplyStatus else { return nil }
            let supplyMember = history.actorName ?? names.supplyMember
            let demandMember = history.actorName ?? names.demandPerson
            let text: String
            var detail: String?
            switch raw {
            case "recommended": text = "\(names.demandCompany) was recommended by Axial."
            case "archived": text = "\(supplyMember) archived the deal."
            case "sent_cim":
                text = "\(supplyMember) sent the CIM."
                detail = history.message
            case "sent_nda": text = "\(names.supplyAccount) sent the NDA."
            case "target_signed_nda": text = "\(demandMember) signed the NDA."
            case "ended_discussions", "target_ended_discussions": text = "\(demandMember) ended discussions."
            case "sent_teaser": text = "\(supplyMember) shared the teaser."
            case "sent_locked": text = "Axial shared the anonymous teaser."
            case "target_expired": text = "\(names.demandCompany) did not pursue or decline within 90 days."
            case "target_declined": text = "\(demandMember) passed on the deal."
            case "target_pursued": text = "\(demandMember) pursued the deal."
            case "target_viewed_nda": text = "\(names.demandCompany) viewed the NDA."
            case "target_viewed_cim": return nil // the download event says it
            default:
                // The web's `_default`: any status it has a label for.
                guard let status = DealStatus(rawValue: raw), status != .unknown else { return nil }
                text = "\(supplyMember) updated the status to \(status.label)."
            }
            return (text, detail, history.date)

        case .event(let event):
            let source = event.sourceUserName ?? event.sourceUserId.flatMap { users[$0] } ?? "Axial Member"
            let target = event.targetUserName ?? event.targetUserId.flatMap { users[$0] } ?? names.demandPerson
            let text: String
            var detail: String?
            switch event.type {
            case "reminded_teaser": text = "\(target) was reminded to respond to the deal."
            case "click_to_call": text = "\(source) called \(target)."
            case "download_document": text = "\(source) viewed a file (\(event.fileName ?? "N/A"))."
            case "cim_link_access":
                let domain = event.link.flatMap { DealProfile.webURL($0)?.host() } ?? "N/A"
                text = "\(source) viewed a link (\(domain))."
            case "request_access":
                text = "\(source) sent \(names.isBuysideReferral ? "you a note regarding this deal" : "an Inbound Inquiry")"
                detail = event.message
            case "approve_access":
                text = "\(source) accepted the \(names.isBuysideReferral ? "Referral" : "Inbound Inquiry") request"
            case "nudge":
                text = "\(source) sent a follow-up."
                detail = event.message
            default: return nil
            }
            return (text, detail, event.date)
        }
    }
}

// MARK: - Comments

/// An internal comment — `IDealNoteData`, from `GET /notes/deal/{id}`.
struct DealNote: Equatable, Identifiable {
    let id: String
    let text: String
    let createdAt: Date
    let authorId: String?
    let authorName: String

    init(id: String, text: String, createdAt: Date, authorId: String? = nil, authorName: String) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.authorId = authorId
        self.authorName = authorName
    }

    init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        text = PlainText.from(html: json["note"]?.string ?? "")
        createdAt = json["created_at"]?.date ?? .distantPast
        let author = json["author"].flatMap(DealProfile.Person.init(json:))
        authorId = author?.id
        authorName = author?.fullName ?? "A teammate"
    }
}

// MARK: - Days

/// The conversation split by calendar day, oldest first, so the Messages
/// tab can head each day once instead of dating every card.
struct DealFeedDay: Identifiable, Equatable {
    let day: Date
    let items: [DealFeedItem]

    var id: Date { day }

    /// Items keep their order; a day starts wherever the date changes.
    static func days(_ items: [DealFeedItem], calendar: Calendar = .current) -> [DealFeedDay] {
        var days: [DealFeedDay] = []
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if let last = days.last, last.day == day {
                days[days.count - 1] = DealFeedDay(day: day, items: last.items + [item])
            } else {
                days.append(DealFeedDay(day: day, items: [item]))
            }
        }
        return days
    }
}
