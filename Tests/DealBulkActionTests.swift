//
//  DealBulkActionTests.swift
//  Tests
//

import Testing
@testable import Axial_Mobile

/// Web source: the `bulkActions` of recommended-, contacted- and
/// interested-members-grid.component.ts, and the bulk confirmations in
/// sell-grid-actions.service.ts.
struct DealBulkActionTests {

    private func deal(_ id: String, _ status: DealStatus = .sentTeaser, interested: Bool = false,
                      pursued: Bool = false) -> SellsideDeal {
        SellsideDeal(publicId: id, supplyStatus: status, isInterested: interested, hasTargetPursued: pursued)
    }

    @Test func nothingSelectedOffersNothing() {
        #expect(DealBulkAction.offered(for: []).isEmpty)
    }

    @Test func recommendationsCanOnlyBePassedOn() {
        #expect(DealBulkAction.offered(for: [deal("a", .recommended), deal("b", .notShared)]) == [.pass])
    }

    @Test func accessRequestsOfferAcceptAndPassOnly() {
        let requests = [deal("a", .targetRequestedAccess, interested: true),
                        deal("b", .targetRequestedAccess, interested: true)]
        #expect(DealBulkAction.offered(for: requests) == [.accept, .pass])
    }

    @Test func contactedMembersUpdateStatusOrEndDiscussions() {
        #expect(DealBulkAction.offered(for: [deal("a"), deal("b", .teaserOpened)]) == [.updateStatus, .endDiscussions])
    }

    @Test func anyEndedMemberSwapsEndForRestart() {
        #expect(DealBulkAction.offered(for: [deal("a"), deal("b", .endedDiscussions)])
                == [.updateStatus, .restartDiscussions])
    }

    @Test func sendCimNeedsOnePursuedInterestedMember() {
        let unpursued = deal("a", .targetSignedNda, interested: true)
        let pursued = deal("b", .targetSignedNda, interested: true, pursued: true)
        #expect(!DealBulkAction.offered(for: [unpursued]).contains(.shareCim))
        #expect(DealBulkAction.offered(for: [unpursued, pursued]).first == .shareCim)
    }

    @Test func bulkStatusMenuDropsExecutedLoiAndClosed() {
        let options = DealBulkAction.statusGroups.flatMap { $0 }
        #expect(!options.contains(.loiExecuted))
        #expect(!options.contains(.successfullyClosed))
        #expect(options.contains(.ndaSent))
    }

    @Test func aStatusUpdateLeavesOutInquiriesAndSaysSo() {
        let copy = BulkStatusCopy(updating: [deal("a"), deal("b", .targetRequestedAccess), deal("c")],
                                  to: .ndaSent, memberType: "contacted")
        #expect(copy.deals.map(\.id) == ["a", "c"])
        #expect(copy.message.hasPrefix("Inbound Inquiries need to be accepted"))
        #expect(copy.message.hasSuffix("mark 2 contacted members as \(DealStatusUpdateOption.ndaSent.label)."))
        #expect(copy.confirm == "Update 2 Members")
    }

    @Test func endingDiscussionsWithOneIsSingular() {
        let copy = BulkStatusCopy(endingDiscussionsWith: [deal("a")], memberType: "interested")
        #expect(copy.message == "You're about to end discussions with 1 interested member.")
        #expect(copy.confirm == "End 1 Discussion")
    }

    @Test func passingOnRecommendationsCountsThem() {
        #expect(RecommendedPassCopy(count: 3).confirm == "Pass on 3 Members")
        #expect(RecommendedPassCopy(count: 1).confirm == "Pass on 1 Member")
    }
}
