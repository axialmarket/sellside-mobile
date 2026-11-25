//
//  DealStatusSectionTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

/// Member lists grouped by status. Held against `gridStatusColumnDefinition`
/// (axl-grid-status-column-definition.ts), which groups by
/// `tableData.displayStatusKey` (supply-deals-row.model.ts) in
/// `SUPPLY_STATUS_FUNNEL_ORDER` (deal.constants.ts).
struct DealStatusSectionTests {

    private func deal(_ id: String, _ status: DealStatus, read: Bool = false,
                      redline: Bool = false) -> SellsideDeal {
        SellsideDeal(publicId: id, supplyStatus: status, demandIsRead: read, hasPendingNdaRedline: redline)
    }

    @Test func sectionsFollowTheFunnelOrder() {
        let sections = DealStatusSection.sections(for: [
            deal("a", .sentTeaser), deal("b", .targetRequestedAccess), deal("c", .sentCim),
        ])
        #expect(sections.map(\.key) == ["target_requested_access", "sent_cim", "sent_teaser"])
    }

    @Test func eachSectionKeepsTheListsOwnOrder() {
        let sections = DealStatusSection.sections(for: [
            deal("a", .sentNda), deal("b", .sentCim), deal("c", .sentNda),
        ])
        #expect(sections.first { $0.key == "sent_nda" }?.deals.map(\.id) == ["a", "c"])
    }

    @Test func markedStatusesShareTheSystemStatusSection() {
        let sections = DealStatusSection.sections(for: [deal("a", .sentNda), deal("b", .markedSentNda)])
        #expect(sections.count == 1)
        #expect(sections[0].title == "NDA Sent")
        #expect(sections[0].deals.count == 2)
    }

    @Test func keysOutsideTheFunnelComeFirstAsOnTheWeb() {
        // `indexOf` gives -1 for Teaser Opened, which sorts it ahead of
        // everything the funnel lists.
        let sections = DealStatusSection.sections(for: [
            deal("a", .targetRequestedAccess), deal("b", .sentTeaser, read: true),
        ])
        #expect(sections.map(\.key) == ["teaser_opened", "target_requested_access"])
    }

    @Test func aPendingRedlineHasItsOwnSection() {
        let sections = DealStatusSection.sections(for: [
            deal("a", .targetSignedNda), deal("b", .sentNda, redline: true),
        ])
        #expect(sections.map(\.key) == ["target_signed_nda", "nda_redlined"])
        #expect(sections[1].title == "NDA Redlined")
    }

    @Test func aHandMarkedStatusHidesTheRedline() {
        #expect(deal("a", .markedNdaSigned, redline: true).displayStatusKey == "target_signed_nda")
    }

    @Test func noDealsMeansNoSections() {
        #expect(DealStatusSection.sections(for: []).isEmpty)
    }
}
