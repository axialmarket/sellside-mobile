//
//  StatusTagTests.swift
//  Tests
//

import SwiftUI
import Testing
@testable import Axial_Mobile

struct StatusTagTests {

    @Test func colorsMatchWebTagAssignments() {
        #expect(StatusTag.colors(for: .inMarket).background == Color(hex: 0xD9F0E5))
        #expect(StatusTag.colors(for: .underReview).background == Color(hex: 0xFCF2D5))
        #expect(StatusTag.colors(for: .readyToShare).background == Color(hex: 0xD6E2FD))
        #expect(StatusTag.colors(for: .reviewingLois).background == Color(hex: 0xFAE4D7))
        #expect(StatusTag.colors(for: .pendingClose).background == Color(hex: 0xFAE4D7))
        #expect(StatusTag.colors(for: .underLoi).background == Color(hex: 0xE8D9FE))
        #expect(StatusTag.colors(for: .draft).background == Color(hex: 0xE5E7EB))
        #expect(StatusTag.colors(for: .unknown).background == Color(hex: 0xE5E7EB))
    }

    @Test func labelsMatchWeb() {
        #expect(SupplyState.inMarket.label == "In Market")
        #expect(SupplyState.reviewingLois.label == "Reviewing LOIs")
        #expect(SupplyState.underLoi.label == "Under LOI")
        #expect(SupplyState.readyToShare.label == "Ready to Share")
    }
}
