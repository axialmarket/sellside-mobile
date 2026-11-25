//
//  ProjectActionsTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

/// Web sources: sell-dashboard action-items/*, sell-sidebar.service.ts,
/// sell-intent.helpers.ts `getBulkAcceptModalTexts`,
/// sell-grid-actions.service.ts, cim-note-sidebar.component.ts,
/// deals.feature.ts, and the project-setup steps the resolve sheets carry.
@MainActor
struct ProjectActionsTests {

    private static let now: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 5; parts.day = 14; parts.hour = 12
        return Calendar.current.date(from: parts)!
    }()

    // MARK: - What a card offers

    @Test func anAccessRequestOffersPassAndAccept() {
        let inquiry = SellsideDeal(publicId: "d", supplyStatus: .targetRequestedAccess)
        let referral = SellsideDeal(publicId: "d", supplyStatus: .targetRequestedAccess, referralSource: "deal")
        #expect(DealResolveAction.offered(for: inquiry) == [.pass, .accept])
        #expect(DealResolveAction.accept.label(for: inquiry) == "Accept Inquiry")
        #expect(DealResolveAction.accept.label(for: referral) == "Accept Referral")
    }

    @Test func aPendingRedlineOffersReviewUnlessTheSellerMarkedTheStatus() {
        let redlined = SellsideDeal(publicId: "d", supplyStatus: .sentNda, hasPendingNdaRedline: true)
        let marked = SellsideDeal(publicId: "d", supplyStatus: .markedSentNda, hasPendingNdaRedline: true)
        #expect(DealResolveAction.offered(for: redlined) == [.reviewRedlines])
        #expect(DealResolveAction.offered(for: marked).isEmpty)
    }

    @Test func aSignedNDAOffersTheCIM() {
        #expect(DealResolveAction.offered(for: .init(publicId: "d", supplyStatus: .targetSignedNda)) == [.shareCim])
        #expect(DealResolveAction.offered(for: .init(publicId: "d", supplyStatus: .sentTeaser)).isEmpty)
    }

    // MARK: - Accept and pass copy

    @Test func bulkAcceptCopyHasThreeVariants() {
        let inquiry = SellsideDeal(publicId: "a", supplyStatus: .targetRequestedAccess)
        let referral = SellsideDeal(publicId: "b", supplyStatus: .targetRequestedAccess, referralSource: "teaser")

        let inquiries = BulkAcceptCopy(deals: [inquiry, inquiry])
        #expect(inquiries.title == "Accept Inquiries")
        #expect(inquiries.confirm == "Accept 2 Inquiries")
        #expect(inquiries.message == "You're about to **accept the inquiries of 2 interested members**, would you like to proceed?")

        let referrals = BulkAcceptCopy(deals: [referral])
        #expect(referrals.title == "Accept Referrals")
        #expect(referrals.confirm == "Accept 1 Referral")

        let mixed = BulkAcceptCopy(deals: [inquiry, referral])
        #expect(mixed.title == "Accept Requests")
        #expect(mixed.message.contains("accept 2 requests and share the NDA"))
    }

    @Test func acceptanceGrowlWordsItselfOffTheResponse() {
        #expect(BulkAcceptCopy.success(count: 1, referralSources: [nil]) == "1 member has been notified of your inquiry acceptance.")
        #expect(BulkAcceptCopy.success(count: 2, referralSources: ["deal", "intent"]) == "2 members have been notified of your referral acceptance.")
        #expect(BulkAcceptCopy.success(count: 2, referralSources: ["deal", nil]) == "2 members have been notified of your request acceptance.")
    }

    @Test func passingOnOneMemberNamesTheAccount() {
        let deal = SellsideDeal(publicId: "d", demandAccountName: "Bluewater Capital", supplyStatus: .targetRequestedAccess)
        #expect(PassCopy(deals: [deal]).message.hasPrefix("You're about to **pass on Bluewater Capital**"))
        #expect(PassCopy(deals: [deal, deal]).confirm == "Pass on 2 Members")
    }

    // MARK: - CIM note

    @Test func theCIMNoteDropsInquiriesAndTheNeverPursued() {
        let ready = SellsideDeal(publicId: "a", demandUserName: "Jordan Reyes", supplyStatus: .targetSignedNda, hasTargetPursued: true)
        let inquiry = SellsideDeal(publicId: "b", supplyStatus: .targetRequestedAccess)
        let unpursued = SellsideDeal(publicId: "c", supplyStatus: .targetSignedNda)
        let recipients = CIMNoteRecipients(deals: [ready, inquiry, unpursued])
        #expect(recipients.eligible.map(\.id) == ["a"])
        #expect(recipients.inquiriesNotice != nil)
        #expect(recipients.ineligibleNotice == "1 member is not eligible to receive the CIM and will be removed from your selection.")
        #expect(recipients.ctaLabel == "Share CIM with Jordan Reyes")
        #expect(CIMNoteRecipients(deals: [ready, ready]).ctaLabel == "Share CIM with 2 Members")
    }

    @Test func theCIMNoteStartsFromTheSavedMessage() {
        #expect(CIMNoteRecipients.message(from: ["cim": ["message": "Hi there"]]) == "Hi there")
        #expect(CIMNoteRecipients.message(from: [:]) == CIMNoteRecipients.defaultMessage)
        #expect(CIMNoteRecipients.files(from: ["cim_type": "linked", "linked_cim": "https://x.com/cim"]) == ["https://x.com/cim"])
    }

    // MARK: - Store calls

    private static let id = "aaabbb"

    private func loadedStore(_ extra: [String: StubAPI.Response]) async -> (ProjectDashboardStore, StubAPI) {
        var responses: [String: StubAPI.Response] = [
            "intents/\(Self.id)": .json(#"{"id": "aaabbb", "internal_name": "Neptune", "supply_state": "in_market"}"#),
            "intents/sellside/\(Self.id)/deals": .json(#"[{"public_id": "d1", "supply_status": "target_requested_access"}, {"public_id": "d2", "supply_status": "target_signed_nda", "has_target_pursued": true}]"#),
        ]
        responses.merge(extra) { $1 }
        let api = StubAPI(responses: responses)
        let store = ProjectDashboardStore(apiClient: api, projectsStore: ProjectsStore(apiClient: api))
        store.refreshesAfterResolving = false
        await store.load(id: Self.id)
        return (store, api)
    }

    @Test func approvingPostsTheIDsAndPatchesTheRow() async throws {
        let (store, api) = await loadedStore([
            "deals/approve-access": .json(#"[{"id": "d1", "supply_status": "sent_nda", "referral": null}]"#),
        ])
        try await store.approveAccess(["d1"], on: Self.id)
        let body = try #require(api.postedBodies["deals/approve-access"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: body) == ["deal_ids": ["d1"]])
        #expect(store.dashboard(for: Self.id)?.deals.first { $0.id == "d1" }?.supplyStatus == .sentNda)
    }

    // SellsideDealApiService.restartDiscussions / passDeals.
    @Test func restartingPostsPublicIDsAndPatchesTheRow() async throws {
        let (store, api) = await loadedStore([
            "deals/restart-discussions": .json(#"[{"id": "d1", "supply_status": "sent_nda"}]"#),
        ])
        try await store.restartDiscussions(["d1"], on: Self.id)
        let body = try #require(api.postedBodies["deals/restart-discussions"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: body) == ["public_ids": ["d1"]])
        #expect(store.dashboard(for: Self.id)?.deals.first { $0.id == "d1" }?.supplyStatus == .sentNda)
    }

    @Test func passingOnRecommendationsUsesTheSellsidePassEndpoint() async throws {
        let (store, api) = await loadedStore(["deals/sellside/pass": .json("[]")])
        try await store.passRecommended(["d1", "d2"], on: Self.id)
        let body = try #require(api.postedBodies["deals/sellside/pass"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: body) == ["public_ids": ["d1", "d2"]])
    }

    @Test func sendingTheCIMMarksAnyoneLeftOutOfTheResponseAsSent() async throws {
        let (store, _) = await loadedStore(["deals/send-cim": .json("[]")])
        try await store.sendCim(SendCIMRequest(message: "Hi", ccMembers: [], dealIds: ["d2"], subject: "Deal"), on: Self.id)
        #expect(store.dashboard(for: Self.id)?.deals.first { $0.id == "d2" }?.supplyStatus == .sentCim)
    }

    @Test func aProjectEditSendsOnlyItsKeysAndAppliesTheResponse() async throws {
        let (store, api) = await loadedStore([:])
        api.responses["intents/\(Self.id)"] = .json(#"{"intent": {"id": "aaabbb", "internal_name": "Neptune", "supply_state": "in_market", "follow_up": {"message": "Hi"}}}"#)
        try await store.updateProject(id: Self.id, patch: ["nudge_days": 5])
        let body = try #require(api.postedBodies["intents/\(Self.id)"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: body) == ["nudge_days": 5])
        #expect(store.dashboard(for: Self.id)?.project.hasFollowUp == true)
    }

    @Test func aRedlineIsPolledUntilItStopsPending() async throws {
        let (store, api) = await loadedStore([
            "documents/deal/d1/submit-redline": .json(#"{"has_pending_nda_redline": true}"#),
        ])
        var sleeps = 0
        await #expect(throws: ProjectDashboardStore.RedlineError.self) {
            try await store.submitRedline(dealId: "d1", on: Self.id, sleep: { _ in sleeps += 1 })
        }
        #expect(sleeps == 19)
        #expect(api.requestedPaths.filter { $0 == "documents/deal/d1/submit-redline" }.count == 20)
    }

    // MARK: - Follow-up note

    @Test func enablingTheFollowUpKeepsTheRestOfTheObject() {
        let intent: JSONValue = ["follow_up": ["message": .null, "subject": "Keep"], "nudge_days": 7]
        var note = FollowUpNote(intent: intent)
        #expect(note.message == FollowUpNote.defaultMessage)
        #expect(note.days == 7)
        note.message = "  Checking in.  "
        #expect(note.patch(over: intent) == ["follow_up": ["message": "Checking in.", "subject": "Keep"], "nudge_days": 7])
        note.message = " "
        #expect(note.errors[FollowUpNote.messageField] != nil)
    }

    // MARK: - CIM upload

    @Test func automaticCIMShareNeedsASignableNDA() {
        let upload = CIMUpload(sharing: "enabled")
        #expect(upload.errors(fileCount: 1, ndaIsSignable: false)[CIMUpload.Field.sharing]
            == "To use Automatic CIM Share, please select an electronically signable NDA.")
        #expect(upload.errors(fileCount: 1, ndaIsSignable: true).isEmpty)
        #expect(CIMUpload().errors(fileCount: 0, ndaIsSignable: true).keys.contains(CIMUpload.Field.materials))
    }

    @Test func theStandardNDAIsSignable() {
        #expect(CIMUpload.ndaIsSignable(intent: ["documents": [["type": "NDA", "is_standard_nda": true]]]))
        #expect(!CIMUpload.ndaIsSignable(intent: ["documents": [["type": "NDA", "signature_type": "download_only"]]]))
        #expect(CIMUpload.ndaIsSignable(intent: ["documents": [["type": "NDA", "signature_type": "basic"]]]))
    }

    @Test func aLinkedCIMSavesAsLinked() {
        #expect(CIMUpload(sharing: "off", linkedURL: "https://x.com").patch
            == ["cim_type": "linked", "linked_cim": "https://x.com", "use_cim_smartshare": false])
        #expect(CIMUpload(sharing: "enabled").patch["cim_type"] == "custom")
    }

    // MARK: - Stale financials

    @Test func closedYearProjectionsOpenEmpty() {
        // FY December, May 2026: 2025 has closed, 2026 hasn't.
        let intent: JSONValue = ["company": ["fiscal_year_end_month": 12, "financials": [
            ["financial_type": "revenue", "time_period": "2025", "is_estimated": true, "value": 9_000_000],
            ["financial_type": "revenue", "time_period": "2026", "is_estimated": true, "value": 10_000_000],
            ["financial_type": "customer_count", "time_period": "na", "is_estimated": false, "value": 40],
        ]]]
        let rows = StaleFinancials.editableRows(intent: intent, now: Self.now)
        #expect(rows.map(\.timePeriod) == ["2025", "2026"])
        #expect(rows.map(\.value) == [nil, 10_000_000])
    }

    @Test func savingKeepsKPIRowsAndTheRestOfCompany() {
        let intent: JSONValue = ["company": ["company_name": "Acme", "financials": [
            ["financial_type": "customer_count", "time_period": "na", "is_estimated": false, "value": 40],
        ]]]
        let rows = [FinancialRow(financialType: "revenue", timePeriod: "2025", value: 2_000_000)]
        let patch = StaleFinancials.patch(over: intent, periodic: rows, fiscalYearEnd: 12)
        #expect(patch["company"]?["company_name"] == "Acme")
        #expect(patch["company"]?["fiscal_year_end_month"] == 12)
        #expect(patch["company"]?["financials"]?.array?.count == 2)
    }

    @Test func theSaveGateNeedsRevenueAndEbitdaInTheLTMOrRecentYear() {
        var table = FinancialTable(rows: [], fiscalYearEnd: 12, now: Self.now, catalog: .empty)
        table.setRaw("5", metric: "revenue", column: .year(2025))
        table.commitAll(catalog: .empty)
        #expect(!table.canSave)
        table.setRaw("1", metric: "ebitda", column: .year(2025))
        table.commitAll(catalog: .empty)
        #expect(table.canSave)
        #expect(table.rows.allSatisfy { !$0.isEstimated })
    }

    @Test func ebitdaAboveRevenueExplainsItselfAndBlocksSave() {
        var table = FinancialTable(rows: [], fiscalYearEnd: 12, now: Self.now, catalog: .empty)
        table.setRaw("5", metric: "revenue", column: .ltm)
        table.setRaw("6", metric: "ebitda", column: .ltm)
        table.commitAll(catalog: .empty)
        #expect(table.hasConflict)
        #expect(table.conflictMessages(catalog: .empty) == ["EBITDA must be less than Revenue"])
    }

    @Test func cellsAreTypedInMillions() {
        #expect(FinancialCellRules.sanitize("$2,500,000", unit: "$") == "2.5")
        #expect(FinancialCellRules.validateStandard("0", metric: "revenue") == .invalidValue)
        #expect(FinancialCellRules.validateStandard("0", metric: "ebitda") == nil)
        #expect(FinancialCellRules.validateStandard("1000", metric: "revenue") == .outOfRange)
    }
}
