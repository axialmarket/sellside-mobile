//
//  MemberBreakdownTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// Web source: fe-app member-breakdown.utils.ts (`groupMembers`),
/// member-breakdown.consts.ts, and `SellDashboardStore.memberBreakdown`.
struct MemberBreakdownTests {

    private func member(_ id: String, code: String? = nil, source: CapitalSource? = nil,
                        closed: Int = 0) -> SellsideDeal {
        SellsideDeal(publicId: id, supplyStatus: .sentTeaser, demandAccountCode: code,
                     capitalSource: source, closedDeals: closed)
    }

    @Test func companyTypesKeepBucketOrderAndDropEmptyOnes() {
        let bars = MemberBreakdown.bars(
            for: [member("1", code: "FO"), member("2", code: "PE"), member("3", code: "PE")],
            by: .companyType
        )
        #expect(bars.map(\.label) == ["Private Equity Fund", "Family Office"])
        #expect(bars.map(\.count) == [2, 1])
    }

    @Test func unlistedAndMissingCompanyTypesFallIntoOther() {
        let bars = MemberBreakdown.bars(
            for: [member("1", code: "IB"), member("2", code: nil), member("3", code: "C")],
            by: .companyType
        )
        #expect(bars.map(\.label) == ["Corporation", "Other"])
        #expect(bars.last?.count == 2)
    }

    @Test func missingAndUnknownCapitalSourcesFallIntoOther() {
        let bars = MemberBreakdown.bars(
            for: [member("1", source: .committed), member("2", source: nil),
                  member("3", source: .other), member("4", source: .unknown)],
            by: .capitalSource
        )
        #expect(bars.map(\.label) == ["Committed", "Other"])
        #expect(bars.last?.count == 3)
    }

    @Test func closedDealsGroupIntoRanges() {
        let bars = MemberBreakdown.bars(
            for: [0, 1, 2, 3, 4, 5, 12].enumerated().map { member("\($0)", closed: $1) },
            by: .closedDeals
        )
        #expect(bars.map(\.label) == ["None", "1-2", "3-4", "5+"])
        #expect(bars.map(\.count) == [1, 2, 2, 2])
    }

    // MARK: - Lists

    private func dashboard(recommended: Int, contacted: Int, interested: Int,
                           autoshare: AutoshareState = .off) -> ProjectDashboard {
        let deals = (0..<recommended).map { SellsideDeal(publicId: "r\($0)", supplyStatus: .recommended) }
            + (0..<contacted).map { SellsideDeal(publicId: "c\($0)", supplyStatus: .sentTeaser) }
            + (0..<interested).map { SellsideDeal(publicId: "i\($0)", supplyStatus: .sentTeaser, isInterested: true) }
        return ProjectDashboard(
            project: ProjectDetail(id: "p1", internalName: "A", autoshareState: autoshare), deals: deals)
    }

    @Test func defaultListPrefersInterestedThenContactedThenRecommended() {
        #expect(MemberBreakdown.defaultList(in: dashboard(recommended: 5, contacted: 5, interested: 2)) == .interested)
        #expect(MemberBreakdown.defaultList(in: dashboard(recommended: 5, contacted: 2, interested: 1)) == .contacted)
        #expect(MemberBreakdown.defaultList(in: dashboard(recommended: 5, contacted: 1, interested: 1)) == .recommended)
        #expect(MemberBreakdown.defaultList(in: dashboard(recommended: 0, contacted: 1, interested: 1)) == .interested)
    }

    @Test func recommendedIsOnlyOfferedWhenThereIsARecList() {
        #expect(MemberBreakdown.availableLists(in: dashboard(recommended: 1, contacted: 0, interested: 0))
                == [.recommended, .contacted, .interested])
        #expect(MemberBreakdown.availableLists(in: dashboard(recommended: 0, contacted: 1, interested: 0))
                == [.contacted, .interested])
        // SmartShare empties the recommended list, so it's not offered either.
        #expect(MemberBreakdown.availableLists(in: dashboard(recommended: 3, contacted: 0, interested: 0,
                                                             autoshare: .enabled))
                == [.contacted, .interested])
    }
}
