//
//  DashboardDecodingTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

/// The fields the dashboard's action items, funnel and breakdown read.
/// Web source: `ISellsideDealsRowData` (supply-deals-row.model.ts) and
/// `ISellsideIntentData` (sellside-intent.interface.ts).
struct DashboardDecodingTests {

    private func deal(_ json: String) throws -> SellsideDeal {
        try JSONDecoder().decode(SellsideDeal.self, from: Data(json.utf8))
    }

    private func project(_ json: String) throws -> ProjectDetail {
        try JSONDecoder().decode(ProjectDetail.self, from: Data(json.utf8))
    }

    // MARK: - Deals

    @Test func progressReadsTrueFlagsAndTreatsFalseNullAndMissingAsNotReached() throws {
        let decoded = try deal("""
        {"public_id": "d1", "progress": {
          "teaser_sent": true, "teaser_opened": true, "interested": false,
          "approved": null, "nda_signed": true, "some_future_stage": true
        }}
        """)
        #expect(decoded.progress.reached == [.teaserSent, .teaserOpened, .ndaSigned])
    }

    @Test func aMissingProgressObjectReachesNothing() throws {
        #expect(try deal(#"{"public_id": "d1"}"#).progress.reached.isEmpty)
    }

    @Test func signedNdaIsPresenceOfTheRecord() throws {
        let signed = try deal(#"{"public_id": "d1", "signed_nda": {"public_id": "n1"}}"#)
        let unsigned = try deal(#"{"public_id": "d1", "signed_nda": null}"#)
        let absent = try deal(#"{"public_id": "d1"}"#)
        #expect(signed.hasSignedNda)
        #expect(!unsigned.hasSignedNda)
        #expect(!absent.hasSignedNda)
    }

    @Test func decodesTheBreakdownFields() throws {
        let decoded = try deal("""
        {"public_id": "d1", "demand_account_code": "FO", "capital_source": "deal_by_deal",
         "buyside_closed_deals": {"value": 4, "uom": "count"}}
        """)
        #expect(decoded.demandAccountCode == "FO")
        #expect(decoded.capitalSource == .dealByDeal)
        #expect(decoded.closedDeals == 4)
    }

    @Test func unknownCapitalSourceDegradesRatherThanFailing() throws {
        #expect(try deal(#"{"public_id": "d1", "capital_source": "crypto"}"#).capitalSource == .unknown)
    }

    @Test func portfolioCompaniesOfPrivateEquityCountAsCorporations() {
        // `companyCode` getter in supply-deals-row.model.ts.
        let portfolio = SellsideDeal(publicId: "d1", demandAccountCode: "PE", demandClientIntentSubtype: "add_on")
        let fund = SellsideDeal(publicId: "d2", demandAccountCode: "PE", demandClientIntentSubtype: "buyside")
        #expect(portfolio.companyCode == "C")
        #expect(fund.companyCode == "PE")
    }

    @Test func aHandMarkedStatusHidesAPendingRedline() {
        // `shouldShowNdaRedline` in deal.constants.ts.
        #expect(SellsideDeal(publicId: "d1", supplyStatus: .sentNda, hasPendingNdaRedline: true).showsNdaRedline)
        #expect(!SellsideDeal(publicId: "d1", supplyStatus: .markedSentNda, hasPendingNdaRedline: true).showsNdaRedline)
    }

    // MARK: - Project

    @Test func hasCimFromAnUploadedOmOrALinkedCim() throws {
        let uploaded = try project("""
        {"id": "p1", "internal_name": "A", "documents": [{"type": "T"}, {"type": "OM"}]}
        """)
        let linked = try project(#"{"id": "p1", "internal_name": "A", "linked_cim": "https://example.com/cim"}"#)
        let neither = try project(#"{"id": "p1", "internal_name": "A", "documents": [{"type": "NDA"}], "linked_cim": ""}"#)
        #expect(uploaded.hasCim)
        #expect(linked.hasCim)
        #expect(!neither.hasCim)
    }

    @Test func followUpIsEnabledOnlyWithAMessage() throws {
        let on = try project(#"{"id": "p1", "internal_name": "A", "follow_up": {"message": "Checking in"}}"#)
        let empty = try project(#"{"id": "p1", "internal_name": "A", "follow_up": {"message": ""}}"#)
        let off = try project(#"{"id": "p1", "internal_name": "A", "follow_up": null}"#)
        #expect(on.hasFollowUp)
        #expect(!empty.hasFollowUp)
        #expect(!off.hasFollowUp)
    }

    @Test func decodesTheCompanyFinancialsAndFiscalYearEnd() throws {
        let decoded = try project("""
        {"id": "p1", "internal_name": "A", "cim_type": "waive", "requires_approval": true,
         "company": {"fiscal_year_end_month": 6, "financials": [
           {"time_period": "2024", "is_estimated": true, "value": 10},
           {"time_period": "ltm", "is_estimated": false}
         ]}}
        """)
        #expect(decoded.cimType == .waive)
        #expect(decoded.requiresApproval)
        #expect(decoded.fiscalYearEndMonth == 6)
        #expect(decoded.financials == [
            FinancialPeriod(timePeriod: "2024", isEstimated: true),
            FinancialPeriod(timePeriod: "ltm", isEstimated: false),
        ])
    }

    @Test func updatedAtIsEpochMilliseconds() throws {
        let millis = (Date.now.timeIntervalSince1970 * 1000).rounded()
        let decoded = try project(#"{"id": "p1", "internal_name": "A", "updated_at": \#(millis)}"#)
        let expected = Date(timeIntervalSince1970: millis / 1000)
        #expect(decoded.updatedAt == expected)
    }
}
