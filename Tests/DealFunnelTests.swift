//
//  DealFunnelTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

/// Web source: fe-app sell-dashboard.store.ts (`funnelStages`),
/// deal-flow-funnel.consts.ts and deal-flow-funnel.model.ts
/// (`buildFunnelStageViews`).
struct DealFunnelTests {

    private func deal(_ id: String, interested: Bool = true, _ reached: Set<FunnelStage>,
                      requiresApproval: Bool = false) -> SellsideDeal {
        SellsideDeal(publicId: id, isInterested: interested,
                     progress: DealProgress(reached: reached), requiresApproval: requiresApproval)
    }

    private func funnel(
        requiresApproval: Bool = false, hasCim: Bool = false, _ deals: [SellsideDeal]
    ) -> DealFunnel {
        DealFunnel(dashboard: ProjectDashboard(
            project: ProjectDetail(id: "p1", internalName: "A", requiresApproval: requiresApproval, hasCim: hasCim),
            deals: deals
        ))
    }

    @Test func approvedAndCimViewedOnlyAppearWhenTheyApply() {
        let base = funnel([]).stages.map(\.stage)
        #expect(!base.contains(.pursued))
        #expect(!base.contains(.cimViewed))
        #expect(base.count == 10)

        #expect(funnel(requiresApproval: true, []).stages.map(\.stage).contains(.pursued))
        #expect(funnel([deal("d1", [], requiresApproval: true)]).stages.map(\.stage).contains(.pursued))
        #expect(funnel(hasCim: true, []).stages.map(\.stage).contains(.cimViewed))
    }

    @Test func everyApplicableStageRendersIncludingZeros() {
        let stages = funnel([]).stages
        #expect(stages.allSatisfy { $0.count == 0 })
        #expect(stages.first?.stage == .teaserSent)
        #expect(stages.last?.stage == .successfullyClosed)
    }

    @Test func stagesPastInterestedCountInterestedMembersOnly() {
        // A seller can mark anyone down the funnel; only interested members count deep.
        let stages = funnel([
            deal("d1", interested: false, [.teaserSent, .teaserOpened, .interested, .ndaSigned]),
            deal("d2", interested: true, [.teaserSent, .ndaSigned]),
        ]).stages
        let count = { (stage: FunnelStage) in stages.first { $0.stage == stage }?.count }
        #expect(count(.teaserSent) == 2)
        #expect(count(.interested) == 1)
        #expect(count(.ndaSigned) == 1)
    }

    @Test func widthsTaperByPositionFromFullToEighteenPercent() {
        let stages = funnel([deal("d1", [.teaserSent])]).stages
        #expect(stages.first?.widthFraction == 1.0)
        #expect(abs((stages.last?.widthFraction ?? 0) - 0.18) < 0.0001)
        // Positional, not count-driven: a stage with more members is no wider.
        #expect(stages[1].widthFraction < stages[0].widthFraction)
    }

    @Test func advanceIsTheRoundedShareOfThePreviousStage() {
        let stages = funnel([
            deal("d1", [.teaserSent, .teaserOpened]),
            deal("d2", [.teaserSent, .teaserOpened]),
            deal("d3", [.teaserSent]),
        ]).stages
        #expect(stages[0].advancePercent == nil)
        #expect(stages[1].advancePercent == 67) // 2 of 3
        #expect(stages[2].advancePercent == 0)  // 0 of 2
        // Previous stage empty: no percentage at all.
        #expect(stages[3].advancePercent == nil)
    }

    @Test func onlyTheTeaserStagesAreNotDrillable() {
        #expect(FunnelStage.allCases.filter { !$0.isDrillable } == [.teaserSent, .teaserOpened])
        // Interested counts everyone but still drills — the two sets differ on purpose.
        #expect(FunnelStage.interested.countsEveryMember)
        #expect(FunnelStage.interested.isDrillable)
    }

    @Test func aStageDrillsToInterestedMembersWhoReachedIt() {
        let board = ProjectDashboard(
            project: ProjectDetail(id: "p1", internalName: "A"),
            deals: [
                deal("d1", interested: true, [.ndaSigned]),
                deal("d2", interested: false, [.ndaSigned]),
                deal("d3", interested: true, [.ndaSent]),
            ]
        )
        #expect(DealSegment.funnelStage(.ndaSigned).deals(in: board).map(\.id) == ["d1"])
    }
}
