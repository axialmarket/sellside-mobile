//
//  DealFilterTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// Web sources: the member grids (contacted/interested/recommended-members
/// -grid.component.ts) for the columns and filters; supply-deals-row.model.ts
/// for `tableData.location` and the last-message rules;
/// axl-grid-company-info-cell-renderer.helpers.ts for `constructCompanyNames`.
struct DealFilterTests {

    // MARK: - Company name

    @Test func aBankersClientIsTheCompanyAndTheBankIsTheSubtitle() {
        let deal = SellsideDeal(publicId: "d1", demandAccountName: "Lakeshore Advisors",
                                demandClientIntentSubtype: "buyside", demandClientName: "Northwind Foods")
        #expect(deal.displayName == "Northwind Foods")
        #expect(deal.companySubtitle == "client of Lakeshore Advisors")
    }

    @Test func aPortfolioCompanyNamesItsSponsor() {
        let deal = SellsideDeal(publicId: "d1", demandAccountName: "Harbor Point Partners",
                                demandClientIntentSubtype: "add_on", demandClientName: nil)
        #expect(deal.displayName == "Anonymous Company")
        #expect(deal.companySubtitle == "Portfolio Co. of Harbor Point Partners")
    }

    @Test func aDirectBuyerIsJustTheAccount() {
        let deal = SellsideDeal(publicId: "d1", demandAccountName: "Bluewater Capital",
                                demandClientIntentSubtype: "direct", demandClientName: "Ignored")
        #expect(deal.displayName == "Bluewater Capital")
        #expect(deal.companySubtitle == nil)
    }

    // MARK: - Card details

    @Test func locationUsesTheStateInNorthAmericaAndTheCountryElsewhere() {
        #expect(SellsideDeal(publicId: "d", city: " Austin ", stateProvince: "TX", country: "US").location == "Austin, TX")
        #expect(SellsideDeal(publicId: "d", city: "Toronto", stateProvince: "ON", country: "CA").location == "Toronto, ON")
        #expect(SellsideDeal(publicId: "d", city: "London", stateProvince: "LND", country: "GB").location == "London, GB")
        #expect(SellsideDeal(publicId: "d", city: nil, country: "US").location == nil)
    }

    @Test func lastMessageNamesTheSenderByFirstName() {
        let deal = SellsideDeal(publicId: "d", lastMessage: "  Sounds good. ", lastMessageFromFullName: "Jordan Reyes")
        #expect(deal.lastMessagePreview == "Jordan: Sounds good.")
    }

    @Test func aLoneEmptyMessageIsNotUnread() {
        #expect(SellsideDeal(publicId: "d", lastMessage: " ", newMessageCount: 1).unreadMessageCount == 0)
        #expect(SellsideDeal(publicId: "d", lastMessage: "Hi", newMessageCount: 1).unreadMessageCount == 1)
        #expect(SellsideDeal(publicId: "d", lastMessage: "", newMessageCount: 3).unreadMessageCount == 3)
    }

    // Mobile's own: the card keeps one line of facts; track record moved to
    // the deal screen.
    @Test func factsJoinTypeAndPlace() {
        let deal = SellsideDeal(publicId: "d", demandAccountCode: "FO", closedDeals: 1,
                                city: "Austin", stateProvince: "TX", country: "US")
        #expect(DealRow.facts(for: deal) == "Family Office · Austin, TX")
        #expect(DealRow.facts(for: SellsideDeal(publicId: "d")) == nil)
    }

    @Test func contactNamesThePersonAndTitleUnlessTheyAreTheTitle() {
        let deal = SellsideDeal(publicId: "d", demandAccountName: "Harbor Point", demandUserName: "Sam Okafor",
                                title: "Principal")
        #expect(DealRow.contact(for: deal) == "Sam Okafor, Principal")
        // A member with no account is titled by their own name already.
        #expect(DealRow.contact(for: SellsideDeal(publicId: "d", demandUserName: "Sam Okafor")) == nil)
    }

    @Test func decodesTheCardFields() throws {
        let deal = try JSONDecoder().decode(SellsideDeal.self, from: Data("""
        {"public_id": "d1", "title": "Partner", "demand_client_name": "Northwind",
         "demand_account_city": "Austin", "demand_account_state_province": "TX", "demand_account_country": "US",
         "last_message": "Hello", "last_message_from_full_name": "Sam Okafor", "new_message_count": 2,
         "demand_user_ratings": {"average": 4.25, "average_count": 4, "mine": null},
         "supply_updated_at": null, "updated_at": "2025-03-04T10:00:00Z", "created_at": "2024-01-01T00:00:00Z"}
        """.utf8))
        #expect(deal.title == "Partner")
        #expect(deal.demandClientName == "Northwind")
        #expect(deal.location == "Austin, TX")
        #expect(deal.unreadMessageCount == 2)
        #expect(deal.averageRating == 4.25)
        // `statusDate` falls back from supply_updated_at to updated_at.
        #expect(deal.statusDate == EpochDate.iso8601("2025-03-04T10:00:00Z"))
    }

    @Test func attributesKeepTheBackendsOrderAndDropUnknownValues() throws {
        // `determineAttributes` (sell.helpers.ts) renders them in array order.
        let deal = try JSONDecoder().decode(SellsideDeal.self, from: Data("""
        {"public_id": "d1", "buyside_attributes": ["highly_responsive_buyer", "brand_new_badge", "axial_closer"]}
        """.utf8))
        #expect(deal.attributes == [.highlyResponsiveBuyer, .axialCloser])
        #expect(try JSONDecoder().decode(SellsideDeal.self, from: Data(#"{"public_id": "d1"}"#.utf8)).attributes.isEmpty)
    }

    @Test func countSummaryShowsTheShareOnlyWhenSomethingIsHidden() {
        #expect(DealFilter.countSummary(shown: 24, total: 24) == "24 members")
        #expect(DealFilter.countSummary(shown: 1, total: 1) == "1 member")
        #expect(DealFilter.countSummary(shown: 6, total: 24) == "6 of 24 members")
        #expect(DealFilter.countSummary(shown: 0, total: 0) == "0 members")
    }

    // MARK: - Filter

    @Test func filtersOrWithinAndAndAcross() {
        let filter = DealFilter(statuses: [.sentTeaser, .targetSignedNda], companyTypes: ["Family Office"])
        #expect(filter.matches(.init(publicId: "d", supplyStatus: .sentTeaser, demandAccountCode: "FO")))
        #expect(filter.matches(.init(publicId: "d", supplyStatus: .targetSignedNda, demandAccountCode: "FO")))
        #expect(!filter.matches(.init(publicId: "d", supplyStatus: .sentTeaser, demandAccountCode: "PE")))
        #expect(!filter.matches(.init(publicId: "d", supplyStatus: .sentCim, demandAccountCode: "FO")))
        #expect(filter.activeCount == 2)
    }

    @Test func statusFiltersOnWhatTheCardShows() {
        // A read teaser shows as Teaser Opened, so that's what it filters as.
        let opened = SellsideDeal(publicId: "d", supplyStatus: .sentTeaser, demandIsRead: true)
        #expect(DealFilter(statuses: [.teaserOpened]).matches(opened))
        #expect(!DealFilter(statuses: [.sentTeaser]).matches(opened))
    }

    @Test func noCapitalSourceFiltersAsOtherAndNoCompanyTypeAsUnspecified() {
        let blank = SellsideDeal(publicId: "d")
        #expect(DealFilter(capitalSources: ["Other"]).matches(blank))
        #expect(DealFilter(companyTypes: [DealFilter.unspecifiedCompanyType]).matches(blank))
    }

    @Test func newMessagesOnlyKeepsUnreadConversations() {
        let filter = DealFilter(hasNewMessages: true)
        #expect(filter.matches(.init(publicId: "d", lastMessage: "Hi", newMessageCount: 1)))
        #expect(!filter.matches(.init(publicId: "d", lastMessage: "Hi", newMessageCount: 0)))
    }

    // MARK: - Search and sort

    @Test func searchCoversCompanyMemberTypePlaceAndMessage() {
        let deals: [SellsideDeal] = [
            .init(publicId: "a", demandAccountName: "Bluewater Capital"),
            .init(publicId: "b", demandUserName: "Jordan Réyes"),
            .init(publicId: "c", demandAccountCode: "SF"),
            .init(publicId: "d", city: "Denver", country: "US"),
            .init(publicId: "e", lastMessage: "Can we see the CIM?"),
        ]
        #expect(DealFilter.matching("bluewater", in: deals).map(\.id) == ["a"])
        #expect(DealFilter.matching("reyes", in: deals).map(\.id) == ["b"])
        #expect(DealFilter.matching("search fund", in: deals).map(\.id) == ["c"])
        #expect(DealFilter.matching("denver", in: deals).map(\.id) == ["d"])
        #expect(DealFilter.matching("cim", in: deals).map(\.id) == ["e"])
        #expect(DealFilter.matching("  ", in: deals).count == 5)
    }

    @Test func mostRecentlyUpdatedComesFirstAndUndatedLast() {
        let now = Date.now
        let deals: [SellsideDeal] = [
            .init(publicId: "old", statusDate: now.addingTimeInterval(-86_400)),
            .init(publicId: "undated"),
            .init(publicId: "new", statusDate: now),
        ]
        #expect(DealFilter.sorted(deals).map(\.id) == ["new", "old", "undated"])
    }

    // MARK: - Options

    @Test func statusOptionsKeepFunnelOrderWithDerivedStatusesInPlace() {
        let options = DealFilterOptions(deals: [
            .init(publicId: "a", supplyStatus: .targetSignedNda),
            .init(publicId: "b", supplyStatus: .sentTeaser, demandIsRead: true),
            .init(publicId: "c", supplyStatus: .sentTeaser),
        ])
        #expect(options.statuses.map(\.value) == [.sentTeaser, .teaserOpened, .targetSignedNda])
    }

    @Test func aSelectionNoLongerPresentStaysVisibleAtZero() {
        let options = DealFilterOptions(
            deals: [.init(publicId: "a", supplyStatus: .sentTeaser, demandAccountCode: "PE")],
            selected: DealFilter(statuses: [.sentCim], companyTypes: ["Family Office"])
        )
        #expect(options.statuses.first { $0.value == .sentCim }?.count == 0)
        #expect(options.companyTypes.map(\.label) == ["Family Office", "Private Equity Fund"])
    }

    @Test func unspecifiedCompanyTypeSortsLast() {
        let options = DealFilterOptions(deals: [
            .init(publicId: "a"), .init(publicId: "b", demandAccountCode: "SF"),
            .init(publicId: "c", demandAccountCode: "C"),
        ])
        #expect(options.companyTypes.map(\.label) == ["Corporation", "Search Fund", DealFilter.unspecifiedCompanyType])
    }

    /// Mobile's own: the breakdown chart's Closed Deals ranges, in its order.
    @Test func closedDealsOptionsUseTheBreakdownRangesInOrder() {
        let options = DealFilterOptions(deals: [
            .init(publicId: "a", closedDeals: 6), .init(publicId: "b", closedDeals: 0),
            .init(publicId: "c", closedDeals: 1),
        ])
        #expect(options.closedDeals.map(\.label) == ["None", "1-2", "5+"])
    }
}
