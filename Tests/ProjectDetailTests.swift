//
//  ProjectDetailTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

struct ProjectDetailTests {

    private func decode(_ json: String) throws -> ProjectDetail {
        try JSONDecoder().decode(ProjectDetail.self, from: Data(json.utf8))
    }

    @Test func decodesTheFieldsTheDashboardRenders() throws {
        let project = try decode("""
        {
          "id": "1350c847f3fd7fadcbd5734197b634bd",
          "internal_name": "Package of Gas Station Retail Locations for Sale",
          "supply_state": "in_market",
          "headline": "Flying cars",
          "created_at": 1492873493000
        }
        """)
        #expect(project.id == "1350c847f3fd7fadcbd5734197b634bd")
        #expect(project.internalName == "Package of Gas Station Retail Locations for Sale")
        #expect(project.supplyState == .inMarket)
    }

    @Test func stripsHyphensSoIdsMatchTheListRow() throws {
        let project = try decode("""
        {"id": "1350c847-f3fd-7fad-cbd5-734197b634bd", "internal_name": "Neptune"}
        """)
        let row = SellsideProject.mock(
            publicId: "1350c847-f3fd-7fad-cbd5-734197b634bd", name: "Neptune"
        )
        #expect(project.id == "1350c847f3fd7fadcbd5734197b634bd")
        #expect(project.id == row.intentId)
    }

    @Test func missingOrUnknownSupplyStateDecodesToUnknown() throws {
        #expect(try decode(#"{"id": "abc", "internal_name": "N"}"#).supplyState == .unknown)
        #expect(try decode(#"{"id": "abc", "internal_name": "N", "supply_state": null}"#)
            .supplyState == .unknown)
        #expect(try decode(#"{"id": "abc", "internal_name": "N", "supply_state": "brand_new"}"#)
            .supplyState == .unknown)
    }

    @Test func listRowAndFetchedProjectProduceTheSameHeader() {
        // The dashboard header renders from the row first, then from the
        // fetched project — so the two must map to the same thing, or the
        // title would visibly change for no reason once the GET lands.
        let row = SellsideProject.mock(
            publicId: "1350c847-f3fd-7fad-cbd5-734197b634bd",
            name: "Project Neptune",
            state: .inMarket
        )
        let detail = ProjectDetail(
            id: "1350c847f3fd7fadcbd5734197b634bd",
            internalName: "Project Neptune",
            supplyState: .inMarket
        )
        #expect(ProjectSummary(row) == ProjectSummary(detail))
    }
}
