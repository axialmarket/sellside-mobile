//
//  MergeTagTests.swift
//  Tests
//

import Testing
@testable import Sellside_Mobile

/// Web source: `TEASER_TOKENS` (token-textarea.constants.ts). The editor
/// shows tags as chips but must save exactly the text the web would.
struct MergeTagTests {

    @Test func splitsAMessageIntoTextAndTags() {
        #expect(MergeTag.segments(in: "{recipient[first_name]},\n\nHi from {assigned_to[full_name]}") == [
            .tag(.recipientFirstName), .text(",\n\nHi from "), .tag(.senderFullName),
        ])
    }

    @Test func unknownBracesStayText() {
        #expect(MergeTag.segments(in: "Hi {recipient[last_name]} {") == [.text("Hi {recipient[last_name]} {")])
    }

    @Test(arguments: [
        "",
        "Plain text",
        "{recipient[first_name]},\n\nI'm following up on the recent deal I shared with you.",
        "{company[name]}{recipient[first_name]}",
        "Ends with a tag {recipient[first_name]}",
    ])
    func segmentsRoundTripToTheSameMessage(_ message: String) {
        #expect(MergeTag.message(from: MergeTag.segments(in: message)) == message)
    }
}
