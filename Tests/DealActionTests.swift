//
//  DealActionTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

/// Held against `actionItems` in fe-app's
/// contacted-members-grid.component.ts, `canFollowUp` (sell.helpers.ts), and
/// the `USER_ACTIONS` → status mapping in sell-actions.service.ts.
struct DealActionTests {

    private func deal(_ status: DealStatus) -> SellsideDeal {
        SellsideDeal(publicId: "d1", supplyStatus: status)
    }

    // MARK: - Availability

    @Test func followUpIsOfferedOnlyOnASentTeaserOrAnExpiredOne() {
        // canFollowUp: [SENT_TEASER, TARGET_EXPIRED]
        #expect(DealAction.sendFollowUp.isAvailable(for: deal(.sentTeaser)))
        #expect(DealAction.sendFollowUp.isAvailable(for: deal(.targetExpired)))

        for status in [DealStatus.targetSignedNda, .markedReceivedLoi, .endedDiscussions, .markedClosed] {
            #expect(!DealAction.sendFollowUp.isAvailable(for: deal(status)),
                    "follow-up offered on \(status.rawValue)")
        }
    }

    @Test func everyOtherActionIsUnconditional() {
        for action in DealAction.allCases where action != .sendFollowUp {
            for status in DealStatus.allCases {
                #expect(action.isAvailable(for: deal(status)))
            }
        }
    }

    @Test func webOrderIsPreserved() {
        #expect(DealAction.available(for: deal(.sentTeaser)) == [
            .sendFollowUp, .updateStatus, .endDiscussions, .addInternalComment, .reportConcern,
        ])
        #expect(DealAction.available(for: deal(.targetSignedNda)) == [
            .updateStatus, .endDiscussions, .addInternalComment, .reportConcern,
        ])
    }

    @Test func onlyTheActionsMobileCanCarryOutAreOffered() {
        // The parity list stays whole; the menu filters it.
        #expect(DealAction.offered(for: deal(.sentTeaser)) == [.updateStatus, .endDiscussions])
        #expect(DealAction.allCases.filter(\.isImplemented) == [.updateStatus, .endDiscussions])
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

    @Test func endingDiscussionsPostsTheEndedStatus() {
        #expect(DealActionRequest.endDiscussions.status == .endedDiscussions)
        #expect(DealActionRequest.updateStatus(.ndaSent).status == .markedSentNda)
    }
}
