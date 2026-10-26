//
//  ProjectSetupAutosaveTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// Web sources: project-setup-save.service.ts (`buildAutosavePayload`,
/// `autosaveWithRetry$`, `performAutosave`), project-setup-intent.utils.ts
/// (`deepDiff`), services/README.md.
@MainActor
struct ProjectSetupAutosaveTests {

    // MARK: - Diff

    @Test func diffRecursesIntoObjectsAndSendsArraysWhole() {
        let baseline: JSONValue = ["a": 1, "company": ["name": "A", "tags": ["x", "y"]], "same": true]
        let current: JSONValue = ["a": 1, "company": ["name": "B", "tags": ["x", "y", "z"]], "same": true]
        #expect(current.diff(from: baseline) == ["company": ["name": "B", "tags": ["x", "y", "z"]]])
    }

    @Test func anUnchangedPayloadDiffsToNothing() {
        let payload: JSONValue = ["a": 1, "b": ["c": .null]]
        #expect(payload.diff(from: payload).isEmptyObject)
    }

    @Test func nullDiffersFromAbsentLikeLodash() {
        #expect(JSONValue.object(["a": .null]).diff(from: .object([:])) == ["a": .null])
    }

    @Test func wholeNumbersEncodeAsIntegers() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["year": 2024, "value": 2.5]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"year\":2024"))
        #expect(text.contains("\"value\":2.5"))
    }

    // MARK: - Payload invariants

    @Test func flippingTheSharingModeSendsBothFlags() {
        let baseline: JSONValue = ["use_smartshare": true, "requires_approval": false]
        let current: JSONValue = ["use_smartshare": false, "requires_approval": false]
        let patch = ProjectSetupSession.autosavePatch(current: current, baseline: baseline, financialsInvalid: false)
        #expect(patch == ["use_smartshare": false, "requires_approval": false])
    }

    @Test func invalidFinancialsStayOutOfAnAutosave() {
        let baseline: JSONValue = ["company": ["financials": [], "company_name": "A"]]
        let current: JSONValue = ["company": ["financials": [["value": 1]], "company_name": "B"]]
        let patch = ProjectSetupSession.autosavePatch(current: current, baseline: baseline, financialsInvalid: true)
        #expect(patch == ["company": ["company_name": "B"]])
    }

    // MARK: - Retry

    @Test func serverErrorsRetryAfterTwoFourAndEightSeconds() async {
        var delays: [Duration] = []
        var attempts = 0
        await #expect(throws: APIError.self) {
            try await ProjectSetupSession.withRetry(sleep: { delays.append($0) }) {
                attempts += 1
                throw APIError.server(503, path: "x", body: nil)
            }
        }
        #expect(attempts == 4)
        #expect(delays == [.seconds(2), .seconds(4), .seconds(8)])
    }

    @Test func clientErrorsAreFinal() async {
        var attempts = 0
        await #expect(throws: APIError.self) {
            try await ProjectSetupSession.withRetry(sleep: { _ in }) {
                attempts += 1
                throw APIError.server(422, path: "x", body: nil)
            }
        }
        #expect(attempts == 1)
        #expect(ProjectSetupSession.message(for: APIError.server(422, path: "x", body: nil)) == "Failed to autosave")
    }

    // MARK: - Session

    private static let id = "abc123"

    private static func intent(supplyState: String = "draft", intentState: String = "draft") -> JSONValue {
        [
            "id": .string(id), "internal_name": "Neptune", "intent_type": "sell_business",
            "supply_state": .string(supplyState), "intent_state": .string(intentState),
            "headline": "", "description": "", "company": ["company_name": "Acme"],
            "updated_at": 1_700_000_000_000,
        ]
    }

    /// The debounce never fires on its own; tests save explicitly.
    private static func session(_ api: StubAPI, intent: JSONValue? = nil) -> ProjectSetupSession {
        ProjectSetupSession(intentId: id, intent: intent ?? Self.intent(), api: api, sleep: { duration in
            if duration == ProjectSetupSession.autosaveDebounce { try await Task.sleep(for: .seconds(3600)) }
        })
    }

    @Test func anAutosaveSendsOnlyWhatChanged() async throws {
        let api = StubAPI(responses: [
            "intents/\(Self.id)/sellside-autosave": .json(#"{"is_complete": false, "last_autosave_success": "2026-01-02T03:04:05Z"}"#),
        ])
        let session = Self.session(api)
        session.form.companyBasics.headline = "A precision machining business"
        await session.triggerAutosave()

        let body = try #require(api.postedBodies["intents/\(Self.id)/sellside-autosave"])
        let sent = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(sent == ["headline": "A precision machining business"])
        #expect(session.autosaveStatus == .saved)
        #expect(session.lastSavedAt == EpochDate.iso8601("2026-01-02T03:04:05Z"))
        #expect(!session.hasUnsavedChanges)
    }

    @Test func nothingChangedMeansNoRequest() async {
        let api = StubAPI()
        let session = Self.session(api)
        await session.triggerAutosave()
        #expect(api.requestedPaths.isEmpty)
    }

    @Test func readOnlyFieldsNeverGoBack() {
        let session = Self.session(StubAPI())
        let payload = session.reviewPayload
        for key in ["id", "supply_state", "intent_state", "updated_at"] {
            #expect(payload[key] == nil)
        }
    }

    @Test func anInMarketProjectDoesNotAutosave() async {
        let api = StubAPI()
        let session = Self.session(api, intent: Self.intent(supplyState: "in_market", intentState: "active"))
        #expect(!session.isAutosaveEnabled)
        session.form.companyBasics.headline = "Changed headline here"
        await session.triggerAutosave()
        #expect(api.requestedPaths.isEmpty)
        #expect(session.reviewLabel == "Review & Save")
    }

    @Test func aFailedAutosaveReportsAndKeepsTheEdit() async {
        let api = StubAPI(responses: [
            "intents/\(Self.id)/sellside-autosave": .failure(APIError.server(400, path: "x", body: nil)),
        ])
        let session = Self.session(api)
        session.form.companyBasics.companyName = "Acme Holdings"
        await session.triggerAutosave()
        #expect(session.autosaveStatus == .error)
        #expect(session.lastSaveError == "Failed to autosave")
        #expect(session.hasUnsavedChanges)
    }

    @Test func pendingDocumentsUploadBeforeTheIntent() async throws {
        let api = StubAPI(responses: [
            "documents/intent/\(Self.id)": .json(#"{"id": "doc-9", "filename": "teaser.pdf", "type": "T"}"#),
            "intents/\(Self.id)/sellside-autosave": .json(#"{"is_complete": false}"#),
        ])
        let session = Self.session(api)
        session.form.documents.add(bucket: "T", filename: "teaser.pdf", mimeType: "application/pdf", data: Data([1, 2]))
        await session.triggerAutosave()
        // Documents first, then the intent call that carries the save.
        #expect(api.requestedPaths == ["documents/intent/\(Self.id)", "intents/\(Self.id)/sellside-autosave"])
        #expect(session.form.documents.pendingUploads.isEmpty)
        #expect(session.form.documents.teaser?.serverID == "doc-9")
    }
}
