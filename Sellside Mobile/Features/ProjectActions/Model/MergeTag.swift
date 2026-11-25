//
//  MergeTag.swift
//  Sellside Mobile
//

import Foundation

/// A merge tag the server fills in per recipient — `TEASER_TOKENS`
/// (token-textarea.constants.ts). The message keeps the raw `{key}` text, as
/// the web's does; the editor shows each one as a chip (`TokenTextView`).
///
/// Only the recipient's first name has an insert button, as on the web. The
/// other two are recognised so a message that already has them, saved from
/// the web, shows chips rather than braces.
enum MergeTag: String, CaseIterable, Hashable {
    case recipientFirstName = "{recipient[first_name]}"
    case companyName = "{company[name]}"
    case senderFullName = "{assigned_to[full_name]}"

    /// The chip's text — the web's token images (gen-tokens.js).
    var label: String {
        switch self {
        case .recipientFirstName: "First name"
        case .companyName: "Company name"
        case .senderFullName: "Sender's full name"
        }
    }

    /// What VoiceOver reads for the chip.
    var spokenLabel: String {
        switch self {
        case .recipientFirstName: "Recipient's first name"
        case .companyName: "Company name"
        case .senderFullName: "Sender's full name"
        }
    }

    /// A run of a message: plain text, or one tag.
    enum Segment: Equatable {
        case text(String)
        case tag(MergeTag)
    }

    /// Splits a message into text and tags, in order. Anything in braces that
    /// isn't a known tag stays text, so nothing is lost on the way back.
    static func segments(in message: String) -> [Segment] {
        var segments: [Segment] = []
        var pending = ""
        var rest = message[...]
        while !rest.isEmpty {
            if rest.first == "{", let tag = allCases.first(where: { rest.hasPrefix($0.rawValue) }) {
                if !pending.isEmpty { segments.append(.text(pending)); pending = "" }
                segments.append(.tag(tag))
                rest = rest.dropFirst(tag.rawValue.count)
            } else {
                pending.append(rest.removeFirst())
            }
        }
        if !pending.isEmpty { segments.append(.text(pending)) }
        return segments
    }

    /// The message again, from its segments.
    static func message(from segments: [Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): text
            case .tag(let tag): tag.rawValue
            }
        }.joined()
    }
}
