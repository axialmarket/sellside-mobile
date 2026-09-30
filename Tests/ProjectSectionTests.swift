//
//  ProjectSectionTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

/// How a project's deals split into its three sections, and which of those
/// the project screen offers a way into.
///
/// Mobile derives all three from the one deals response, where the web uses
/// two endpoints — so this is the seam most likely to be wrong against real
/// data, and each test says plainly what rule it's claiming.
struct ProjectSectionTests {

    private func dashboard(
        autoshare: AutoshareState = .off,
        deals: [SellsideDeal] = []
    ) -> ProjectDashboard {
        ProjectDashboard(
            project: ProjectDetail(
                id: "abc", internalName: "Neptune",
                supplyState: .inMarket, autoshareState: autoshare
            ),
            deals: deals
        )
    }

    // MARK: - Bucketing

    @Test func interestedWinsOverEverythingElse() {
        // `is_interested` is what lifts a deal out of Contacted on the web.
        let deal = SellsideDeal(publicId: "d1", supplyStatus: .sentTeaser, isInterested: true)
        #expect(deal.bucket == .interested)
    }

    @Test func aNeverSharedDealIsARecommendation() {
        for status in [DealStatus.recommended, .notShared] {
            #expect(SellsideDeal(publicId: "d1", supplyStatus: status).bucket == .recommended)
        }
    }

    @Test func everythingElseIsContacted() {
        let contacted: [DealStatus] = [
            .sentTeaser, .sentLocked, .targetRequestedAccess, .targetPursued,
            .sentNda, .targetSignedNda, .sentCim, .markedReceivedLoi,
            .markedClosed, .endedDiscussions, .targetExpired, .targetDeclined,
        ]
        for status in contacted {
            #expect(SellsideDeal(publicId: "d1", supplyStatus: status).bucket == .contacted,
                    "\(status.rawValue) was not bucketed as contacted")
        }
    }

    @Test func anUnrecognizedStatusFallsIntoContactedRatherThanVanishing() {
        #expect(SellsideDeal(publicId: "d1", supplyStatus: .unknown).bucket == .contacted)
    }

    @Test func everyDealLandsInExactlyOneSection() {
        let board = dashboard(deals: DealStatus.allCases.enumerated().map { index, status in
            SellsideDeal(
                publicId: "d\(index)", supplyStatus: status, isInterested: index.isMultiple(of: 5)
            )
        })
        let ids = SellsideDeal.Bucket.allCases.flatMap { board.deals(in: $0).map(\.id) }
        #expect(ids.count == board.deals.count)
        #expect(Set(ids).count == ids.count, "a deal appeared in more than one section")
    }

    @Test func sectionsReadInFunnelOrder() {
        #expect(SellsideDeal.Bucket.allCases == [.recommended, .contacted, .interested])
    }

    // MARK: - SmartShare

    @Test func smartShareEmptiesTheRecommendedSection() {
        // Axial is sharing the teaser automatically, so there's no list to
        // work through — web returns [] for the same reason.
        let deals: [SellsideDeal] = [.init(publicId: "d1", supplyStatus: .recommended)]
        #expect(dashboard(autoshare: .enabled, deals: deals).recommendedDeals.isEmpty)
    }

    @Test func otherAutoshareStatesDoNotEmptyIt() {
        let deals: [SellsideDeal] = [.init(publicId: "d1", supplyStatus: .recommended)]
        for state in AutoshareState.allCases where state != .enabled {
            #expect(dashboard(autoshare: state, deals: deals).recommendedDeals.count == 1,
                    "\(state.rawValue) emptied the section")
        }
    }

    @Test func smartShareDoesNotTouchTheOtherSections() {
        let board = dashboard(autoshare: .enabled, deals: [
            .init(publicId: "d1", supplyStatus: .sentTeaser),
            .init(publicId: "d2", supplyStatus: .targetSignedNda, isInterested: true),
        ])
        #expect(board.contactedDeals.count == 1)
        #expect(board.interestedDeals.count == 1)
    }

    // MARK: - Which sections the project screen links to

    @Test func recommendedIsTheOnlyConditionalSection() {
        #expect(dashboard().populatedSections == [.contacted, .interested])

        let withRecs = dashboard(deals: [.init(publicId: "d1", supplyStatus: .recommended)])
        #expect(withRecs.populatedSections == [.recommended, .contacted, .interested])
    }

    @Test func recommendedDisappearsOnceEverythingHasBeenShared() {
        let board = dashboard(deals: [.init(publicId: "d1", supplyStatus: .sentTeaser)])
        #expect(!board.populatedSections.contains(.recommended))
    }

    @Test func smartShareAlsoRemovesTheRecommendedLink() {
        // Nothing to navigate to, so no card promising otherwise.
        let board = dashboard(
            autoshare: .enabled, deals: [.init(publicId: "d1", supplyStatus: .recommended)]
        )
        #expect(!board.populatedSections.contains(.recommended))
    }

    @Test func emptyContactedAndInterestedSectionsStillLink() {
        // An empty list is information; a missing card is a question.
        #expect(dashboard().populatedSections.contains(.contacted))
        #expect(dashboard().populatedSections.contains(.interested))
    }

    // MARK: - Actions per section

    @Test func recommendedDealsOfferNoContactedGridActions() {
        let recommended = SellsideDeal(publicId: "d1", supplyStatus: .recommended)
        #expect(DealAction.offered(for: recommended).isEmpty)

        let contacted = SellsideDeal(publicId: "d2", supplyStatus: .sentTeaser)
        #expect(DealAction.offered(for: contacted) == [.updateStatus, .endDiscussions])
    }
}
