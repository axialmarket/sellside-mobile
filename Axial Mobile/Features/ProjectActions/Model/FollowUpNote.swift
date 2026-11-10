//
//  FollowUpNote.swift
//  Axial Mobile
//

import Foundation

/// The Enable Follow-Up action item's edit — the Follow-Up Note segment of
/// the web's Marketing Settings step (marketing-settings.service.ts and
/// `extractMessagingFromForm`), on its own.
struct FollowUpNote: Equatable {
    var message: String
    /// `nudge_days`, 3–20 business days.
    var days: Int

    static let defaultMessage = "{recipient[first_name]},\n\nI'm following up on the recent deal I shared with you. If you are interested in learning more, please indicate your interest to move forward."
    static let dayOptions = Array(3...20)

    /// Hydrates as the web does: an existing message, else the default; the
    /// saved days, else 3.
    init(intent: JSONValue) {
        message = intent["follow_up"]?["message"]?.text ?? Self.defaultMessage
        days = intent["nudge_days"]?.int.map { min(max($0, 3), 20) } ?? 3
    }

    init(message: String, days: Int) {
        self.message = message
        self.days = days
    }

    /// Enabled is inferred from a message being present, so enabling is
    /// writing one. `follow_up` goes whole, so its other keys survive.
    func patch(over intent: JSONValue) -> JSONValue {
        var followUp = intent["follow_up"]?.object ?? [:]
        followUp["message"] = .string(message.trimmingCharacters(in: .whitespacesAndNewlines))
        return ["follow_up": .object(followUp), "nudge_days": .number(Double(days))]
    }

    static let messageField: FormFieldKey = "followUp.message"

    /// The web has no validator here — but an empty message *is* "disabled",
    /// so enabling with one would do nothing.
    var errors: [FormFieldKey: String] {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [Self.messageField: "Add a message to enable the follow-up note."]
            : [:]
    }
}

/// Merge tags (`TEASER_TOKENS`). Only the first has an insert button.
enum MergeTag {
    static let recipientFirstName = "{recipient[first_name]}"
}
