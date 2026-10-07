//
//  ProjectActionItemsTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// Web source: fe-app sell-dashboard.store.ts, `SellDashboardStore.actionItems`
/// and the predicates it reads; action-items.model.ts for the priority order.
struct ProjectActionItemsTests {

    private func dashboard(
        state: SupplyState = .inMarket,
        intentState: IntentState = .active,
        cimType: CimType? = .custom,
        hasCim: Bool = true,
        hasFollowUp: Bool = true,
        updatedAt: Date? = .now,
        financials: [FinancialPeriod] = [],
        fiscalYearEndMonth: Int? = nil,
        deals: [SellsideDeal] = []
    ) -> ProjectDashboard {
        ProjectDashboard(
            project: ProjectDetail(
                id: "p1", internalName: "Neptune", supplyState: state, intentState: intentState,
                cimType: cimType, hasCim: hasCim, hasFollowUp: hasFollowUp, updatedAt: updatedAt,
                financials: financials, fiscalYearEndMonth: fiscalYearEndMonth
            ),
            deals: deals
        )
    }

    private func kinds(_ dashboard: ProjectDashboard, now: Date = .now) -> [ProjectActionItem.Kind] {
        ProjectActionItem.items(for: dashboard, now: now).map(\.kind)
    }

    /// Exact 24-hour days, as `daysSinceLastActivity` counts them — a
    /// calendar day across a DST change is an hour short and floors to one
    /// fewer.
    private func daysAgo(_ days: Int, from now: Date = .now) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    // MARK: - Gating

    @Test func aQuietWellSetUpProjectHasNothingToDo() {
        #expect(kinds(dashboard()).isEmpty)
    }

    @Test func itemsOnlyAppearInMarketOrReadyToShare() {
        let pending = [SellsideDeal(publicId: "d1", supplyStatus: .targetRequestedAccess)]
        #expect(kinds(dashboard(state: .inMarket, deals: pending)) == [.approveMembers])
        #expect(kinds(dashboard(state: .readyToShare, deals: pending)) == [.approveMembers])
        for state: SupplyState in [.draft, .underReview, .reviewingLois, .underLoi, .closed, .dead, .onHold, .unknown] {
            #expect(kinds(dashboard(state: state, deals: pending)).isEmpty, "\(state)")
        }
    }

    @Test func itemsComeOutInPriorityOrder() {
        let deals: [SellsideDeal] = [
            .init(publicId: "d1", supplyStatus: .targetRequestedAccess),
            .init(publicId: "d2", supplyStatus: .sentNda, hasPendingNdaRedline: true),
            .init(publicId: "d3", supplyStatus: .targetSignedNda, hasTargetPursued: true, hasSignedNda: true),
        ]
        let items = kinds(dashboard(hasFollowUp: false, deals: deals))
        #expect(items == [.approveMembers, .reviewNdaRedlines, .sendCim, .enableFollowUp])
    }

    // MARK: - Counts and copy

    @Test func approveMembersCountsAndPluralises() {
        let one = ProjectActionItem.items(for: dashboard(deals: [
            .init(publicId: "d1", supplyStatus: .targetRequestedAccess),
        ]))
        #expect(one.first?.title == "Review 1 member awaiting approval")
        #expect(one.first?.description == "1 member requested approval and is awaiting your review.")

        let two = ProjectActionItem.items(for: dashboard(deals: [
            .init(publicId: "d1", supplyStatus: .targetRequestedAccess),
            .init(publicId: "d2", supplyStatus: .targetRequestedAccess),
        ]))
        #expect(two.first?.title == "Review 2 members awaiting approval")
        #expect(two.first?.control == .segment(.pendingApproval))
    }

    @Test func sendCimNeedsPursuitAndACimToSend() {
        let signed = SellsideDeal(publicId: "d1", supplyStatus: .markedNdaSigned, hasTargetPursued: true, hasSignedNda: true)
        let unpursued = SellsideDeal(publicId: "d2", supplyStatus: .targetSignedNda, hasSignedNda: true)
        #expect(kinds(dashboard(deals: [signed])) == [.sendCim])
        // Requested access isn't enough for the server's `can_send_cim`.
        #expect(kinds(dashboard(deals: [unpursued])).isEmpty)
        // No CIM yet: the prompt is to upload one instead.
        #expect(kinds(dashboard(cimType: nil, hasCim: false, deals: [signed])) == [.uploadCim])
    }

    @Test func uploadCimTreatsAWaivedCimAsNone() {
        let signed = SellsideDeal(publicId: "d1", supplyStatus: .sentCim, hasSignedNda: true)
        #expect(kinds(dashboard(cimType: .waive, hasCim: false, deals: [signed])) == [.uploadCim])
        #expect(kinds(dashboard(cimType: .linked, deals: [signed])).isEmpty)
    }

    // MARK: - Update project status

    @Test func aClosedMemberPromptsClosingTheProject() {
        let items = ProjectActionItem.items(for: dashboard(deals: [
            .init(publicId: "d1", supplyStatus: .markedClosed, isInterested: true),
            .init(publicId: "d2", supplyStatus: .markedExecutedLoi, isInterested: true),
        ]))
        // Closed wins when both apply.
        #expect(items.map(\.control) == [.status(.closed, ctaLabel: "Project is Closed")])
    }

    @Test func anExecutedLoiPromptsPausingNewInterest() {
        let items = ProjectActionItem.items(for: dashboard(deals: [
            .init(publicId: "d1", supplyStatus: .markedExecutedLoi, isInterested: true),
        ]))
        #expect(items.map(\.control) == [.status(.underLoi, ctaLabel: "Pause New Interest")])
    }

    @Test func onlyInterestedMembersTriggerTheStatusPrompt() {
        let items = kinds(dashboard(deals: [
            .init(publicId: "d1", supplyStatus: .markedClosed, isInterested: false),
        ]))
        #expect(items.isEmpty)
    }

    @Test func theStatusPromptNeverAsksAProjectToStepBack() {
        let loi = SellsideDeal(publicId: "d1", supplyStatus: .markedExecutedLoi, isInterested: true)
        let closed = SellsideDeal(publicId: "d2", supplyStatus: .markedClosed, isInterested: true)
        // Already Under LOI: an executed LOI asks nothing more…
        #expect(kinds(dashboard(state: .underLoi, deals: [loi])).isEmpty)
        // …but a close still moves it forward. The prompt survives downfunnel states.
        #expect(ProjectActionItem.items(for: dashboard(state: .underLoi, deals: [closed])).map(\.control)
                == [.status(.closed, ctaLabel: "Project is Closed")])
        #expect(kinds(dashboard(state: .pendingClose, deals: [closed])).isEmpty)
    }

    @Test func theStatusPromptIsHiddenWhereANudgeIsMeaningless() {
        let closed = SellsideDeal(publicId: "d1", supplyStatus: .markedClosed, isInterested: true)
        for state: SupplyState in [.onHold, .dead, .draft, .underReview, .unknown] {
            #expect(kinds(dashboard(state: state, deals: [closed])).isEmpty, "\(state)")
        }
    }

    @Test func aQuietActiveProjectGetsTheStaleNudgeAtSixtyDays() {
        let now = Date.now
        let stale = ProjectActionItem.items(for: dashboard(updatedAt: daysAgo(60, from: now)), now: now)
        #expect(stale.map(\.control) == [.statusMenu])
        #expect(stale.first?.description.contains("quiet for 60 days") == true)
        #expect(kinds(dashboard(updatedAt: daysAgo(59, from: now)), now: now).isEmpty)
    }

    @Test func theStaleNudgeReadsIntentStateNotSupplyState() {
        // Matches the backend email's population: `intent_state == 'active'`.
        let now = Date.now
        let archived = dashboard(state: .inMarket, intentState: .archived, updatedAt: daysAgo(90, from: now))
        #expect(kinds(archived, now: now).isEmpty)
        let reviewing = dashboard(state: .reviewingLois, updatedAt: daysAgo(90, from: now))
        #expect(kinds(reviewing, now: now) == [.updateProjectStatus])
    }

    @Test func theDealPromptWinsOverTheStaleNudge() {
        let now = Date.now
        let items = ProjectActionItem.items(for: dashboard(updatedAt: daysAgo(90, from: now), deals: [
            .init(publicId: "d1", supplyStatus: .markedExecutedLoi, isInterested: true),
        ]), now: now)
        #expect(items.map(\.control) == [.status(.underLoi, ctaLabel: "Pause New Interest")])
    }

    // MARK: - Stale financials

    @Test func projectionsForACompletedFiscalYearAreStale() {
        let now = Date.now
        let thisYear = Calendar.current.component(.year, from: now)
        let financials = [
            FinancialPeriod(timePeriod: String(thisYear - 2), isEstimated: true),
            FinancialPeriod(timePeriod: String(thisYear - 2), isEstimated: true),
            FinancialPeriod(timePeriod: String(thisYear - 3), isEstimated: false),
            FinancialPeriod(timePeriod: String(thisYear + 1), isEstimated: true),
            FinancialPeriod(timePeriod: "ltm", isEstimated: true),
        ]
        let project = ProjectDetail(id: "p1", internalName: "A", financials: financials)
        #expect(project.staleFinancialYears(now: now) == [thisYear - 2])
        #expect(kinds(dashboard(financials: financials), now: now) == [.updateStaleFinancials])
    }

    @Test func aFiscalYearEndingThisMonthHasNotCompletedYet() {
        // `mostRecentCompletedFyYear`: a year completes once its end month has passed.
        let now = Date.now
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let estimate = [FinancialPeriod(timePeriod: String(year), isEstimated: true)]

        let endsThisMonth = ProjectDetail(id: "p1", internalName: "A", financials: estimate, fiscalYearEndMonth: month)
        #expect(endsThisMonth.staleFinancialYears(now: now).isEmpty)
        if month > 1 {
            let endedLastMonth = ProjectDetail(id: "p1", internalName: "A", financials: estimate,
                                               fiscalYearEndMonth: month - 1)
            #expect(endedLastMonth.staleFinancialYears(now: now) == [year])
        }
    }

    // MARK: - Segments match their counts

    @Test func eachSegmentListsExactlyTheMembersItsItemCounted() {
        let deals: [SellsideDeal] = [
            .init(publicId: "d1", supplyStatus: .targetRequestedAccess),
            .init(publicId: "d2", supplyStatus: .targetRequestedAccess, isInterested: true),
            .init(publicId: "d3", supplyStatus: .targetSignedNda, hasTargetPursued: true),
            .init(publicId: "d4", supplyStatus: .targetSignedNda),
        ]
        let board = dashboard(deals: deals)
        #expect(DealSegment.pendingApproval.deals(in: board).map(\.id) == ["d1", "d2"])
        #expect(DealSegment.awaitingCim.deals(in: board).map(\.id) == ["d3"])
        let titles = ProjectActionItem.items(for: board).map(\.title)
        #expect(titles.contains("Review 2 members awaiting approval"))
        #expect(titles.contains("Send the CIM to 1 member"))
    }
}
