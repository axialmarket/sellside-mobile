//
//  MessageDraft.swift
//  Axial Mobile
//

import Foundation

/// The signed-in Axial user — `GET /api/users/me`. Messages go out from
/// them, and their own comments are the ones they can delete.
struct CurrentUser: Equatable {
    let id: String
    let email: String
    let fullName: String

    init(id: String, email: String, fullName: String) {
        self.id = id
        self.email = email
        self.fullName = fullName
    }

    init?(json: JSONValue) {
        guard let person = DealProfile.Person(json: json), let email = person.email,
              let id = json["id"]?.string ?? json["public_id"]?.string else { return nil }
        self.id = id
        self.email = email
        fullName = person.fullName
    }
}

/// A reply on the Messages tab, prefilled the way the web's composer is
/// (`MessagesFeedSendingComponent.setDefaultRecipients` and
/// `setDefaultSubjectAndBody`).
///
/// What mobile leaves out: CC (the web fills it from the project's extra
/// contacts, which mobile doesn't model), attachments, and the anonymous
/// teaser case where the reply goes to whoever shared it. Those replies go
/// to the buyer's primary contact instead, which is the web's fallback.
struct MessageDraft: Equatable {
    var to: [DealMessage.Recipient]
    var subject: String
    var body: String

    /// `determineTo` for a plain Reply: everyone on the latest message bar
    /// you, cut to its sender unless you sent it — or, if you weren't on it,
    /// the buyer's primary contact.
    static func reply(latest: DealMessage?, me: CurrentUser?, contact: DealProfile.Person?,
                      headline: String?) -> MessageDraft {
        var to: [DealMessage.Recipient] = []
        if let latest, let me, latest.involves(me.email) {
            to = ([latest.from] + latest.to).filter { $0.email.caseInsensitiveCompare(me.email) != .orderedSame }
            if to.count > 1, latest.from.email.caseInsensitiveCompare(me.email) != .orderedSame {
                to = Array(to.prefix(1))
            }
        } else if let contact, let email = contact.email {
            to = [DealMessage.Recipient(userId: contact.id, name: contact.fullName, email: email)]
        }
        var seen = Set<String>()
        to = to.filter { seen.insert($0.email.lowercased()).inserted }

        let subject = latest?.subject.map { "Re: " + $0.replacingOccurrences(of: "^Re:\\s?", with: "",
                                                                             options: .regularExpression) }
        return MessageDraft(to: to, subject: subject ?? headline ?? "", body: "")
    }

    var canSend: Bool {
        !to.isEmpty && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `POST /api/messaging/messages`, as `createMessage` sends it:
    /// `thread_id` is always blank, because the endpoint reads it as a root
    /// thread id the client never has, and threads the reply by deal.
    func request(dealId: String, from me: CurrentUser) -> SendMessageRequest {
        SendMessageRequest(messages: [.init(
            dealId: dealId,
            threadId: "",
            from: .init(userId: me.id, email: me.email, name: nil),
            recipients: .init(to: to.map { .init(userId: $0.userId, email: $0.email, name: $0.name) }, cc: [], bcc: []),
            subject: subject,
            body: PlainText.html(from: body.trimmingCharacters(in: .whitespacesAndNewlines)),
            attachments: [],
            templateId: "",
            messageType: "user_message"
        )])
    }
}

extension DealMessage {
    /// `Message.isPartyToEmail`.
    func involves(_ email: String) -> Bool {
        ([from] + to + cc).contains { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }
}

/// `{ messages: IMessageCreate[] }`.
struct SendMessageRequest: Encodable, Equatable {
    struct Message: Encodable, Equatable {
        let dealId: String
        let threadId: String
        let from: Recipient
        let recipients: Recipients
        let subject: String
        let body: String
        let attachments: [String]
        let templateId: String
        let messageType: String

        enum CodingKeys: String, CodingKey {
            case from, recipients, subject, body, attachments
            case dealId = "deal_id"
            case threadId = "thread_id"
            case templateId = "template_id"
            case messageType = "message_type"
        }
    }

    struct Recipient: Encodable, Equatable {
        let userId: String?
        let email: String
        let name: String?

        enum CodingKeys: String, CodingKey {
            case email, name
            case userId = "user_id"
        }
    }

    struct Recipients: Encodable, Equatable {
        let to: [Recipient]
        let cc: [Recipient]
        let bcc: [Recipient]
    }

    let messages: [Message]
}
