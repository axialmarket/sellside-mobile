//
//  SellsideProjectTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

struct SellsideProjectTests {

    static let fullRowJSON = """
    {
        "public_id": "abc-123",
        "internal_name": "Project Neptune",
        "supply_state": "in_market",
        "intent_type": "sell_business",
        "sectors": [{"vertical": 1, "activity": 2, "name": "Industrials"}],
        "active_recommendations": 24,
        "unread_recommendations": 3,
        "active_deals": 12,
        "interested_members": 5,
        "assigned_to_user": {"public_id": "u-1", "first_name": "Jordan", "last_name": "Reyes"},
        "created_at": "2026-08-30T12:00:00Z",
        "counterparty_name": "extra fields are ignored"
    }
    """

    @Test func decodesFullRow() throws {
        let project = try JSONDecoder().decode(SellsideProject.self, from: Data(Self.fullRowJSON.utf8))
        #expect(project.publicId == "abc-123")
        #expect(project.internalName == "Project Neptune")
        #expect(project.supplyState == .inMarket)
        #expect(project.intentType == "sell_business")
        #expect(project.sectors.map(\.name) == ["Industrials"])
        #expect(project.activeRecommendations == 24)
        #expect(project.unreadRecommendations == 3)
        #expect(project.activeDeals == 12)
        #expect(project.interestedMembers == 5)
        #expect(project.assignedToUser?.fullName == "Jordan Reyes")
        #expect(project.createdAt != nil)
    }

    @Test func unknownSupplyStateFallsBackToUnknown() throws {
        let json = Self.fullRowJSON.replacingOccurrences(of: "\"in_market\"", with: "\"brand_new_state\"")
        let project = try JSONDecoder().decode(SellsideProject.self, from: Data(json.utf8))
        #expect(project.supplyState == .unknown)
    }

    @Test func minimalRowDecodes() throws {
        let json = """
        {"public_id": "x", "internal_name": "Bare"}
        """
        let project = try JSONDecoder().decode(SellsideProject.self, from: Data(json.utf8))
        #expect(project.supplyState == .unknown)
        #expect(project.sectors.isEmpty)
        #expect(project.unreadRecommendations == nil)
        #expect(project.assignedToUser == nil)
        #expect(project.createdAt == nil)
        #expect(project.activeRecommendations == 0)
    }

    @Test func fractionalSecondsDateDecodes() throws {
        let json = Self.fullRowJSON.replacingOccurrences(
            of: "2026-08-30T12:00:00Z", with: "2026-08-30T12:00:00.123Z")
        let project = try JSONDecoder().decode(SellsideProject.self, from: Data(json.utf8))
        #expect(project.createdAt != nil)
    }

    @Test func epochDateDecodes() throws {
        let json = Self.fullRowJSON.replacingOccurrences(
            of: "\"2026-08-30T12:00:00Z\"", with: "1756555200")
        let project = try JSONDecoder().decode(SellsideProject.self, from: Data(json.utf8))
        #expect(project.createdAt == Date(timeIntervalSince1970: 1_756_555_200))
    }
}
