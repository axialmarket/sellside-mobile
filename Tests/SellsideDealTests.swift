//
//  SellsideDealTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

struct SellsideDealTests {

    @Test func decodesTheFieldsTheDashboardUses() throws {
        let deals = try JSONDecoder().decode([SellsideDeal].self, from: Data("""
        [{
          "public_id": "d1",
          "supply_intent_public_id": "i1",
          "demand_account_public_id": "a1",
          "demand_account_name": "Bluewater Capital",
          "demand_user_name": "Jordan Reyes",
          "is_interested": true,
          "is_anonymous": false,
          "supply_status": "sent_teaser"
        }]
        """.utf8))
        #expect(deals.count == 1)
        #expect(deals[0].demandAccountName == "Bluewater Capital")
        #expect(deals[0].isInterested)
    }

    @Test func toleratesMissingOptionalFields() throws {
        let deals = try JSONDecoder().decode([SellsideDeal].self, from: Data("""
        [{"public_id": "d1"}]
        """.utf8))
        #expect(deals[0].demandAccountPublicId == nil)
        #expect(deals[0].isInterested == false)
        #expect(deals[0].isAnonymous == false)
    }

    @Test func decodesTheNestedReferralSource() throws {
        let deals = try JSONDecoder().decode([SellsideDeal].self, from: Data("""
        [{"public_id": "d1", "supply_status": "target_requested_access",
          "referral": {"referral_source": "teaser"}}]
        """.utf8))
        #expect(deals[0].referralSource == "teaser")
        #expect(deals[0].isActiveBuysideReferral)
    }

    @Test func anUnrecognizedStatusDecodesToUnknown() throws {
        let deals = try JSONDecoder().decode([SellsideDeal].self, from: Data("""
        [{"public_id": "d1", "supply_status": "invented_last_tuesday"}]
        """.utf8))
        #expect(deals[0].supplyStatus == .unknown)
    }

    // MARK: - Display status
    //
    // Mirrors tableData.displayStatusKey in supply-deals-row.model.ts.

    @Test func aReadTeaserReadsAsOpened() {
        let sent = SellsideDeal(publicId: "d1", supplyStatus: .sentTeaser, demandIsRead: false)
        let read = SellsideDeal(publicId: "d2", supplyStatus: .sentTeaser, demandIsRead: true)
        #expect(sent.displayStatus == .sentTeaser)
        #expect(read.displayStatus == .teaserOpened)
        #expect(read.displayStatus.label == "Teaser Opened")
    }

    @Test func aBuysideReferralReadsAsReferralReceived() {
        for source in ["deal", "teaser"] {
            let deal = SellsideDeal(
                publicId: "d1", supplyStatus: .targetRequestedAccess, referralSource: source
            )
            #expect(deal.displayStatus == .referralReceived)
        }
    }

    @Test func anInboundInquiryIsNotAReferral() {
        // Same status, no referral source — web calls this an inbound inquiry.
        let deal = SellsideDeal(publicId: "d1", supplyStatus: .targetRequestedAccess)
        #expect(!deal.isActiveBuysideReferral)
        #expect(deal.displayStatus == .targetRequestedAccess)
        #expect(deal.displayStatus.label == "Inquiry Received")
    }

    @Test func anOtherSourcedReferralIsNotABuysideReferral() {
        let deal = SellsideDeal(
            publicId: "d1", supplyStatus: .targetRequestedAccess, referralSource: "advisor"
        )
        #expect(!deal.isActiveBuysideReferral)
    }

    @Test func markedStatusesCollapseOntoTheirSystemEquivalent() {
        let pairs: [(DealStatus, DealStatus)] = [
            (.markedSentNda, .sentNda),
            (.markedSentCim, .sentCim),
            (.markedTargetDeclined, .targetDeclined),
            (.markedNdaSigned, .targetSignedNda),
        ]
        for (marked, system) in pairs {
            let deal = SellsideDeal(publicId: "d1", supplyStatus: marked)
            #expect(deal.displayStatus == system)
            // ...and read identically either way, which is the point.
            #expect(marked.label == system.label)
        }
    }

    @Test func everyOtherStatusDisplaysAsItself() {
        let collapsed: Set<DealStatus> = [
            .markedSentNda, .markedSentCim, .markedTargetDeclined, .markedNdaSigned,
        ]
        for status in DealStatus.allCases where !collapsed.contains(status) {
            let deal = SellsideDeal(publicId: "d1", supplyStatus: status)
            #expect(deal.displayStatus == status, "\(status.rawValue) changed on display")
        }
    }

    // MARK: - Display name

    @Test func fallsBackFromCompanyToContactToAPlaceholder() {
        #expect(SellsideDeal(publicId: "d", demandAccountName: "Bluewater",
                             demandUserName: "Jordan Reyes").displayName == "Bluewater")
        #expect(SellsideDeal(publicId: "d", demandAccountName: "",
                             demandUserName: "Jordan Reyes").displayName == "Jordan Reyes")
        #expect(SellsideDeal(publicId: "d", isAnonymous: true).displayName == "Anonymous Buyer")
        #expect(SellsideDeal(publicId: "d").displayName == "Unnamed Member")
    }

    // MARK: - Patching

    @Test func applyingAnUpdateChangesOnlyWhatCameBack() {
        let deal = SellsideDeal(
            publicId: "d1", demandAccountName: "Bluewater",
            supplyStatus: .sentTeaser, demandIsRead: true, isInterested: true
        )
        let updated = deal.applying(
            DealStatusUpdate(id: "d1", supplyStatus: .markedNdaSigned, demandIsRead: nil)
        )
        #expect(updated.supplyStatus == .markedNdaSigned)
        #expect(updated.demandIsRead)          // absent from the response, so kept
        #expect(updated.isInterested)          // never in the response at all
        #expect(updated.demandAccountName == "Bluewater")
    }
}
