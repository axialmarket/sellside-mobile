//
//  CounterpartyTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

/// Mirrors fe-app's `parsePossibleCounterParties` / `filterCompanies` and the
/// payload built by `submitForm` in
/// update-intent-with-counterparty-modal.component.ts.
struct CounterpartyTests {

    @Test func onePerCompanySortedByName() {
        let options = CounterpartyOption.options(from: [
            .init(publicId: "d1", demandAccountPublicId: "a2", demandAccountName: "Zenith Partners"),
            .init(publicId: "d2", demandAccountPublicId: "a1", demandAccountName: "Bluewater Capital"),
        ])
        #expect(options.map(\.name) == ["Bluewater Capital", "Zenith Partners"])
        #expect(options.map(\.accountId) == ["a1", "a2"])
    }

    @Test func keepsTheFirstDealPerAccount() {
        // Two contacts at one company is one counterparty.
        let options = CounterpartyOption.options(from: [
            .init(publicId: "d1", demandAccountPublicId: "a1", demandAccountName: "Bluewater Capital"),
            .init(publicId: "d2", demandAccountPublicId: "a1", demandAccountName: "Bluewater Capital"),
        ])
        #expect(options.count == 1)
    }

    @Test func dropsDealsWithoutAnAccount() {
        // Web calls these imported contacts and filters them out.
        let options = CounterpartyOption.options(from: [
            .init(publicId: "d1", demandAccountPublicId: nil, demandAccountName: "Ghost Co"),
            .init(publicId: "d2", demandAccountPublicId: "", demandAccountName: "Empty Co"),
            .init(publicId: "d3", demandAccountPublicId: "a1", demandAccountName: "Real Co"),
        ])
        #expect(options.map(\.name) == ["Real Co"])
    }

    @Test func sortIsCaseInsensitive() {
        let options = CounterpartyOption.options(from: [
            .init(publicId: "d1", demandAccountPublicId: "a1", demandAccountName: "alpha"),
            .init(publicId: "d2", demandAccountPublicId: "a2", demandAccountName: "Beta"),
        ])
        #expect(options.map(\.name) == ["alpha", "Beta"])
    }

    // MARK: - Request body

    private func encoded(_ info: CounterpartyInfo) throws -> [String: Any] {
        let data = try JSONEncoder().encode(info)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func pickingAMemberSendsTheAccountIdAndNoName() throws {
        let body = try encoded(.make(
            selection: .member("a1"), customName: "ignored", sourcedViaAxial: true
        ))
        #expect(body["account_public_id"] as? String == "a1")
        #expect(body["name"] == nil)
        #expect(body["is_sourced_via_axial"] as? Bool == true)
    }

    @Test func outsideAxialSendsTheTypedNameAndNoAccountId() throws {
        let body = try encoded(.make(
            selection: .outsideAxial, customName: "  Harbor Point  ", sourcedViaAxial: false
        ))
        #expect(body["name"] as? String == "Harbor Point")
        #expect(body["account_public_id"] == nil)
        #expect(body["is_sourced_via_axial"] as? Bool == false)
    }

    @Test func blankNamesAreOmittedRatherThanSentEmpty() throws {
        for typed in ["", "   "] {
            let body = try encoded(.make(
                selection: .outsideAxial, customName: typed, sourcedViaAxial: true
            ))
            #expect(body["name"] == nil)
        }
    }

    @Test func theCounterpartyItselfIsOptional() throws {
        // Web only validates the sourcing question, so this is a legal submit.
        let body = try encoded(.make(selection: .unspecified, customName: "", sourcedViaAxial: true))
        #expect(body["name"] == nil)
        #expect(body["account_public_id"] == nil)
        #expect(body["is_sourced_via_axial"] as? Bool == true)
    }
}
