//
//  DealActionTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

/// Held against `actionItems` and `quickButtonOrder` in fe-app's
/// recommended-, contacted- and interested-members-grid.component.ts, and
/// the `USER_ACTIONS` → status mapping in sell-actions.service.ts.
struct DealActionTests {

    private func deal(_ status: DealStatus) -> SellsideDeal {
        SellsideDeal(publicId: "d1", supplyStatus: status)
    }

    // MARK: - Row actions

    @Test func aRecommendationCanOnlyBePassedOn() {
        // recommended-members-grid: Draft Outreach Note (web-only), Pass.
        #expect(DealRowAction.menu(for: deal(.notShared)) == [.pass])
        #expect(DealRowAction.quick(for: deal(.notShared)) == [.pass])
    }

    @Test func anAccessRequestOffersAcceptThenPass() {
        let request = SellsideDeal(publicId: "d1", supplyStatus: .targetRequestedAccess, isInterested: true)
        #expect(DealRowAction.menu(for: request) == [.accept, .pass])
        #expect(DealRowAction.quick(for: request) == [.accept, .pass])
    }

    @Test func aContactedMemberLeadsWithUpdateStatus() {
        // contacted-members-grid: Update Status is the quick button.
        #expect(DealRowAction.menu(for: deal(.sentTeaser)) == [.updateStatus, .endDiscussions])
        #expect(DealRowAction.quick(for: deal(.sentTeaser)) == [.updateStatus])
    }

    @Test func anEndedMemberRestartsInsteadOfEnding() {
        #expect(DealRowAction.menu(for: deal(.endedDiscussions)) == [.updateStatus, .restartDiscussions])
    }

    @Test func aSignedInterestedMemberLeadsWithSendCim() {
        // interested-members-grid: Share CIM is quick button 0 once the NDA
        // is signed; Update Status otherwise.
        let signed = SellsideDeal(publicId: "d1", supplyStatus: .targetSignedNda, isInterested: true)
        let teaser = SellsideDeal(publicId: "d2", supplyStatus: .sentTeaser, isInterested: true)
        #expect(DealRowAction.menu(for: signed) == [.shareCim, .updateStatus, .endDiscussions])
        #expect(DealRowAction.quick(for: signed) == [.shareCim])
        #expect(DealRowAction.quick(for: teaser) == [.updateStatus])
    }

    @Test func aWaitingRedlineLeadsBothMenus() {
        let redlined = SellsideDeal(publicId: "d1", supplyStatus: .targetSignedNda, isInterested: true,
                                    hasPendingNdaRedline: true)
        #expect(DealRowAction.menu(for: redlined).first == .reviewRedlines)
        #expect(DealRowAction.quick(for: redlined) == [.reviewRedlines, .shareCim])
    }

    /// Mobile's own split of the web's quick buttons across the two swipe
    /// edges: Pass on its own side, away from Accept.
    @Test func anAccessRequestSwipesRightToPassAndLeftToAccept() {
        let request = SellsideDeal(publicId: "d1", supplyStatus: .targetRequestedAccess, isInterested: true)
        #expect(DealRowAction.leadingSwipe(for: request) == [.pass])
        #expect(DealRowAction.trailingSwipe(for: request) == [.accept])
    }

    @Test func onlyAnAccessRequestHasALeadingSwipe() {
        for status in DealStatus.allCases where status != .targetRequestedAccess {
            for interested in [false, true] {
                let deal = SellsideDeal(publicId: "d", supplyStatus: status, isInterested: interested)
                #expect(DealRowAction.leadingSwipe(for: deal).isEmpty, "\(status.rawValue)")
                #expect(DealRowAction.trailingSwipe(for: deal) == DealRowAction.quick(for: deal))
            }
        }
    }

    @Test func everyQuickActionIsAlsoInTheMenu() {
        for status in DealStatus.allCases {
            for interested in [false, true] {
                let deal = SellsideDeal(publicId: "d", supplyStatus: status, isInterested: interested)
                let menu = DealRowAction.menu(for: deal)
                #expect(DealRowAction.quick(for: deal).allSatisfy(menu.contains), "\(status.rawValue)")
            }
        }
    }

    // MARK: - Actions sheet

    @Test func aSignedInterestedMemberGetsCimMessageAndEndAsTiles() {
        let signed = SellsideDeal(publicId: "d1", supplyStatus: .targetSignedNda, isInterested: true)
        let layout = DealActionsLayout(deal: signed)
        #expect(layout.tiles == [.action(.shareCim), .compose(.message), .action(.endDiscussions)])
        #expect(layout.sections == [
            [.action(.updateStatus)],
            [.compose(.comment)],
            [.view(.profile), .view(.messages), .view(.files), .view(.comments)],
        ])
    }

    @Test func aTeaserOffersNoFollowUp() {
        // No per-deal follow-up on the web; the project sends it.
        let layout = DealActionsLayout(deal: deal(.sentTeaser))
        #expect(layout.tiles == [.action(.updateStatus), .compose(.comment), .action(.endDiscussions)])
        // No reply before they're interested, though the thread can be read.
        #expect(!layout.sections.flatMap(\.self).contains(.compose(.message)))
        #expect(layout.sections.flatMap(\.self).contains(.view(.messages)))
    }

    @Test func theDestructiveTileIsAlwaysLast() {
        let request = SellsideDeal(publicId: "d1", supplyStatus: .targetRequestedAccess, isInterested: true)
        #expect(DealActionsLayout(deal: request).tiles.last == .action(.pass))
        #expect(DealActionsLayout(deal: deal(.notShared)).tiles.last == .action(.pass))
    }

    @Test func noItemIsBothATileAndARow() {
        for status in DealStatus.allCases {
            for interested in [false, true] {
                let layout = DealActionsLayout(deal: SellsideDeal(publicId: "d", supplyStatus: status,
                                                                  isInterested: interested))
                #expect(layout.tiles.count <= 4)
                #expect(Set(layout.tiles).isDisjoint(with: layout.sections.flatMap(\.self)), "\(status.rawValue)")
            }
        }
    }

    // MARK: - Status updates

    @Test func theFunnelMatchesTheWebsOrderAndLabels() {
        let options = DealStatusUpdateOption.groups.flatMap(\.self)
        #expect(options == DealStatusUpdateOption.allCases)
        #expect(options.map(\.label) == [
            "NDA Sent", "NDA Signed", "CIM Sent",
            "IOI Received", "LOI Received", "LOI Executed",
            "Member Declined", "Successfully Closed",
        ])
    }

    @Test func eachOptionPostsTheStatusTheWebPosts() {
        #expect(DealStatusUpdateOption.ndaSent.status == .markedSentNda)
        #expect(DealStatusUpdateOption.ndaSigned.status == .markedNdaSigned)
        #expect(DealStatusUpdateOption.cimSent.status == .markedSentCim)
        #expect(DealStatusUpdateOption.ioiReceived.status == .markedReceivedIoi)
        #expect(DealStatusUpdateOption.loiReceived.status == .markedReceivedLoi)
        #expect(DealStatusUpdateOption.loiExecuted.status == .markedExecutedLoi)
        #expect(DealStatusUpdateOption.memberDeclined.status == .markedTargetDeclined)
        #expect(DealStatusUpdateOption.successfullyClosed.status == .markedClosed)
    }

    @Test func separatorsLandWhereTheWebPutsThem() {
        // Web breaks after mark_cim_sent and mark_loi_executed.
        #expect(DealStatusUpdateOption.groups.map { $0.last?.status } == [
            .markedSentCim, .markedExecutedLoi, .markedClosed,
        ])
    }

    @Test func aMarkedStatusCountsAsItsTwinWhenTickingTheCurrentOne() {
        // Marked NDA Sent shows as "NDA Sent", the same as the automatic one.
        #expect(DealStatusUpdateOption.ndaSent.isCurrent(for: deal(.markedSentNda)))
        #expect(DealStatusUpdateOption.ndaSent.isCurrent(for: deal(.sentNda)))
        #expect(!DealStatusUpdateOption.ndaSigned.isCurrent(for: deal(.sentNda)))
    }

    @Test func endingDiscussionsPostsTheEndedStatus() {
        #expect(DealActionRequest.endDiscussions.status == .endedDiscussions)
        #expect(DealActionRequest.updateStatus(.ndaSent).status == .markedSentNda)
    }
}
