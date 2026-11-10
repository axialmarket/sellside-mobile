//
//  ProjectStatusDetailTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// The status popover's contents. Held against `updateHoverData`,
/// `getSubtitle`, `currentSharingSetting` and `smartshareExpiryInDays` in
/// fe-app's sell-intent-status-tag.component.ts and intent.model.ts.
struct ProjectStatusDetailTests {

    /// Fixed so the relative subtitles are deterministic.
    private let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    private func project(
        supplyState: SupplyState = .inMarket,
        intentState: IntentState = .active,
        autoshare: AutoshareState = .off,
        autoshareExpiresAt: Date? = nil,
        inboundInquiry: Bool = false,
        lastDraftDate: Date? = nil,
        inReviewDate: Date? = nil,
        inMarketDate: Date? = nil,
        underLoiDate: Date? = nil,
        inboundInquiryDate: Date? = nil
    ) -> ProjectDetail {
        ProjectDetail(
            id: "abc", internalName: "Neptune",
            supplyState: supplyState, intentState: intentState,
            autoshareState: autoshare, autoshareExpiresAt: autoshareExpiresAt,
            isInboundInquiryEnabled: inboundInquiry,
            lastDraftDate: lastDraftDate, inReviewDate: inReviewDate,
            inMarketDate: inMarketDate, underLoiDate: underLoiDate,
            inboundInquiryDate: inboundInquiryDate
        )
    }

    // MARK: - Status row

    @Test func anAgedStatusReadsAsDaysOnAxial() {
        let detail = ProjectStatusDetail(
            project: project(inMarketDate: daysAgo(43)), now: now
        )
        #expect(detail.rows[0].title == "In Market")
        #expect(detail.rows[0].subtitle == "43 days on Axial")
    }

    @Test func oneDayIsSingular() {
        let detail = ProjectStatusDetail(project: project(inMarketDate: daysAgo(1)), now: now)
        #expect(detail.rows[0].subtitle == "1 day on Axial")
    }

    /// Formatted the way the subtitles are, so these assertions don't depend
    /// on the machine's time zone — a literal "December 12, 2025" passes in
    /// UTC and fails in New York.
    private func formatted(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year())
    }

    @Test func draftAndUnderLoiReadAsADateInstead() {
        // Web sets shortDateSubtitle on exactly these two.
        let draft = ProjectStatusDetail(
            project: project(supplyState: .draft, lastDraftDate: daysAgo(20)), now: now
        )
        #expect(draft.rows[0].subtitle == "Since \(formatted(daysAgo(20)))")

        let loi = ProjectStatusDetail(
            project: project(supplyState: .underLoi, underLoiDate: daysAgo(5)), now: now
        )
        #expect(loi.rows[0].subtitle == "Since \(formatted(daysAgo(5)))")
        // ...and specifically not the age form the other statuses use.
        #expect(loi.rows[0].subtitle?.contains("on Axial") == false)

        for state in SupplyState.allCases where state != .draft && state != .underLoi {
            #expect(!state.usesShortDateSubtitle, "\(state.rawValue) unexpectedly uses a date")
        }
    }

    @Test func eachStatusReadsTheDateFieldTheWebGivesIt() {
        #expect(SupplyState.draft.statusDateField == .lastDraft)
        #expect(SupplyState.inMarket.statusDateField == .inMarket)
        #expect(SupplyState.reviewingLois.statusDateField == .inReview)
        #expect(SupplyState.underLoi.statusDateField == .underLoi)
        // Web keys under_review to the inbound-inquiry date; mirrored, not fixed.
        #expect(SupplyState.underReview.statusDateField == .inboundInquiry)

        for state in [SupplyState.readyToShare, .pendingClose, .closed, .onHold, .dead, .unknown] {
            #expect(state.statusDateField == nil, "\(state.rawValue) gained a date field")
        }
    }

    @Test func aStatusWithNoDateGetsNoSubtitle() {
        // Both the "status has no date field" and "field is unset" cases.
        #expect(ProjectStatusDetail(project: project(supplyState: .closed), now: now)
            .rows[0].subtitle == nil)
        #expect(ProjectStatusDetail(project: project(supplyState: .inMarket), now: now)
            .rows[0].subtitle == nil)
    }

    // MARK: - Sharing row

    @Test func anActiveProjectAlsoShowsHowItIsBeingShared() {
        let detail = ProjectStatusDetail(project: project(inMarketDate: daysAgo(43)), now: now)
        #expect(detail.rows.count == 2)
        #expect(detail.rows[1].title == "Manual Review")
        #expect(detail.rows[1].subtitle == nil)
    }

    @Test func anInactiveProjectShowsOnlyItsStatus() {
        // Sharing settings are meaningless on a draft or an archived deal.
        for state in [IntentState.draft, .archived, .closed, .underLoi, .unknown] {
            let detail = ProjectStatusDetail(project: project(intentState: state), now: now)
            #expect(detail.rows.count == 1, "\(state.rawValue) showed a sharing row")
        }
    }

    @Test func smartShareCountsDownTheDaysRemaining() {
        let detail = ProjectStatusDetail(
            project: project(autoshare: .enabled, autoshareExpiresAt: now.addingTimeInterval(12 * 86_400)),
            now: now
        )
        #expect(detail.rows[1].title == "SmartShare")
        #expect(detail.rows[1].subtitle == "Active for 12 more days")
    }

    @Test func anExpiredSmartShareFloorsAtZeroRatherThanGoingNegative() {
        let detail = ProjectStatusDetail(
            project: project(autoshare: .enabled, autoshareExpiresAt: daysAgo(3)), now: now
        )
        #expect(detail.rows[1].subtitle == "Active for 0 more days")
    }

    @Test func inboundInquiryOutranksSmartShare() {
        // Web checks inbound inquiry first in currentSharingSetting.
        let detail = ProjectStatusDetail(
            project: project(
                autoshare: .enabled,
                autoshareExpiresAt: now.addingTimeInterval(86_400),
                inboundInquiry: true,
                inboundInquiryDate: daysAgo(20)
            ),
            now: now
        )
        #expect(detail.rows[1].title == "Inbound Inquiry")
        #expect(detail.rows[1].subtitle == "Active since \(formatted(daysAgo(20)))")
    }

    @Test func inboundInquiryWithoutADateShowsNoSubtitle() {
        let detail = ProjectStatusDetail(project: project(inboundInquiry: true), now: now)
        #expect(detail.rows[1].subtitle == nil)
    }

    @Test func smartShareOnlyCountsDownWhileItIsEnabled() {
        for state in AutoshareState.allCases where state != .enabled {
            let detail = ProjectStatusDetail(
                project: project(autoshare: state, autoshareExpiresAt: now.addingTimeInterval(86_400)),
                now: now
            )
            #expect(detail.rows[1].title == "Manual Review", "\(state.rawValue) read as SmartShare")
        }
    }
}

/// The intent date fields are JS millisecond timestamps.
struct EpochDateTests {

    private struct Fixture: Decodable {
        let when: Date?
        enum CodingKeys: String, CodingKey { case when }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            when = EpochDate.decode(c, forKey: .when)
        }
    }

    private func decode(_ json: String) throws -> Date? {
        try JSONDecoder().decode(Fixture.self, from: Data(json.utf8)).when
    }

    @Test func numbersAreMillisecondsNotSeconds() throws {
        // 1492873493000 is 2017, not 1970 — the trap this exists to avoid.
        let date = try #require(try decode(#"{"when": 1492873493000}"#))
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        #expect(year == 2017)
    }

    @Test func zeroAndNullMeanUnset() throws {
        #expect(try decode(#"{"when": 0}"#) == nil)
        #expect(try decode(#"{"when": null}"#) == nil)
        #expect(try decode(#"{}"#) == nil)
    }

    @Test func isoStringsAreAcceptedToo() throws {
        // Not every endpoint sends numbers — list rows send ISO strings.
        #expect(try decode(#"{"when": "2017-04-22T14:24:53Z"}"#) != nil)
        #expect(try decode(#"{"when": "2017-04-22T14:24:53.123Z"}"#) != nil)
    }

    @Test func nonsenseStringsDecodeToNilRatherThanThrowing() throws {
        #expect(try decode(#"{"when": "not a date"}"#) == nil)
    }
}
