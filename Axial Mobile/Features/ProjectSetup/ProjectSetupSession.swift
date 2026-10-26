//
//  ProjectSetupSession.swift
//  Axial Mobile
//

import Foundation
import Observation

/// The web's `ProjectSetupStore` + `ProjectSetupFormService` +
/// `ProjectSetupSaveService` + `DocumentsStore`, for one open wizard.
/// Created when setup opens, discarded when it closes — never app-scoped,
/// because two projects' wizard state must never mix (the web scopes its
/// store to the container for the same reason).
///
/// The form is one value (`SetupForm`), so every edit is a single `didSet`:
/// validation recomputes, and — while the project is in an autosaving state
/// — the autosave debounce restarts.
@Observable
final class ProjectSetupSession {
    enum AutosaveStatus: Equatable {
        case idle, saving, saved, error
    }

    let intentId: String
    private(set) var context: SetupContext
    /// The intent as last confirmed by the server, as raw JSON — the base
    /// every payload is written over, so fields mobile doesn't model survive.
    private(set) var intent: JSONValue

    var form: SetupForm {
        didSet {
            guard form != oldValue else { return }
            validation = SetupValidator.validate(form, context: context)
            isDirty = true
            formDidChange()
        }
    }

    private(set) var validation: SetupValidation
    /// `showValidationErrors` — set by Review, never cleared within a session.
    private(set) var showsValidationErrors = false
    private(set) var touched: Set<SetupFieldKey> = []
    /// Edited since the last save. The web's `form.dirty`.
    private(set) var isDirty = false

    private(set) var autosaveStatus: AutosaveStatus = .idle
    /// The indicator only appears once the first autosave has begun.
    private(set) var hasStartedAutosave = false
    private(set) var lastSavedAt: Date?
    /// The most recent failure, for the indicator's detail and the close guard.
    private(set) var lastSaveError: String?

    // Reference data, loaded alongside the wizard.
    private(set) var members: [AccountMember] = []
    private(set) var catalog: FinancialCatalog = .empty
    private(set) var catalogFailed = false

    // MARK: Autosave internals

    /// The form-derived payload as of the last successful save — the diff
    /// anchor. `lastSavedIntentData`.
    private var baseline: JSONValue
    private var debounce: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// `formChangedDuringSave` → `followUpAutosaveRequested`.
    private var changedDuringSave = false

    private let api: any APIRequesting
    private let sleep: (Duration) async throws -> Void
    private let now: () -> Date

    static let autosaveDebounce: Duration = .milliseconds(850)
    static let maxRetryAttempts = 3
    static let autosaveEligibleStates: Set<String> = ["draft", "under_review", "ready_to_share", "auto_draft"]

    init(
        intentId: String,
        intent: JSONValue,
        api: any APIRequesting,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.intentId = intentId
        self.intent = intent
        self.api = api
        self.sleep = sleep
        self.now = now
        let context = SetupContext(intent: intent, now: now())
        self.context = context
        let form = SetupForm(intent: intent, context: context)
        self.form = form
        self.validation = SetupValidator.validate(form, context: context)
        // Seeded from the form, not the raw intent: the form applies UI
        // defaults (`initializeBaseline`'s overlay), and diffing the first
        // edit against the API's value would send those defaults as changes.
        self.baseline = form.payload(over: intent, context: context)
        self.lastSavedAt = intent["last_autosave_success"]?.string.flatMap(EpochDate.iso8601)
    }

    // MARK: - Reference data

    /// Members (Primary Contact, CC lists) and the financial-type catalog.
    /// Neither blocks the wizard: a failure leaves that control empty.
    func loadReferenceData() async {
        async let members: Void = loadMembers()
        async let catalog: Void = loadCatalog()
        _ = await (members, catalog)
    }

    private func loadMembers() async {
        let accountID = intent["owned_by_account_public_id"]?.string ?? intent["owned_by_account"]?["id"]?.string
        guard let accountID else { return }
        do {
            let loaded: [AccountMember] = try await api.get("accounts/\(accountID)/members",
                                                            query: [URLQueryItem(name: "is_active", value: "false")],
                                                            headers: [:])
            members = loaded
            context.memberCount = loaded.count
            validation = SetupValidator.validate(form, context: context)
        } catch {
            members = []
        }
    }

    func loadCatalog() async {
        catalogFailed = false
        do {
            let response: FinancialCatalog.Response = try await api.get("metadata/financial-types")
            catalog = FinancialCatalog(response)
            // Not an edit: the KPI rows just learn their units.
            // Rescaling KPI text to millions leaves the payload unchanged.
            withoutAutosave(rebaseline: false) { $0.financials.applyCatalog(catalog) }
        } catch {
            catalogFailed = true
        }
    }

    func member(_ id: String?) -> AccountMember? {
        members.first { $0.matches(id) }
    }

    /// Applies a change that isn't the member's edit — hydration, document
    /// ids coming back — without dirtying the form or scheduling a save.
    private func withoutAutosave(rebaseline: Bool = true, _ change: (inout SetupForm) -> Void) {
        var copy = form
        change(&copy)
        let wasDirty = isDirty
        suppressAutosave = true
        form = copy
        suppressAutosave = false
        isDirty = wasDirty
        if rebaseline { baseline = form.payload(over: intent, context: context) }
    }

    private var suppressAutosave = false

    // MARK: - Errors

    /// The message to show under a field, or nil. Errors appear once a field
    /// has been touched, or once Review has revealed them all.
    func visibleError(for field: SetupFieldKey) -> String? {
        guard showsValidationErrors || touched.contains(field) || validation.immediate.contains(field) else {
            return nil
        }
        return validation.errors[field]
    }

    func isRequired(_ field: SetupFieldKey) -> Bool {
        validation.required.contains(field)
    }

    func touch(_ field: SetupFieldKey) {
        if !touched.contains(field) { touched.insert(field) }
    }

    /// True when validation is showing and any of `fields` is invalid — a
    /// segment's red border (`invalidSegmentFragments`).
    func segmentHasError(_ fields: [SetupFieldKey]) -> Bool {
        guard showsValidationErrors else { return false }
        return fields.contains { validation.errors[$0] != nil }
    }

    /// `revealValidationErrors` — Review & Share, or a link from the
    /// incomplete-steps list.
    func revealValidationErrors() {
        showsValidationErrors = true
    }

    // MARK: - Progress

    func steps(in section: SetupSection) -> [SetupStep] {
        context.steps(in: section)
    }

    func progress(for step: SetupStep) -> StepProgress {
        validation.progress[step] ?? StepProgress(required: 0, completed: 0)
    }

    func sectionHasError(_ section: SetupSection) -> Bool {
        showsValidationErrors && steps(in: section).contains { progress(for: $0).isInvalid }
    }

    var completion: SetupCompletion {
        SetupCompletion(incompleteSteps: context.sequence.filter { progress(for: $0).isInvalid })
    }

    /// `reviewCTALabel` — from the *saved* sharing setting, as on the web.
    var reviewLabel: String {
        if context.isInMarket { return "Review & Save" }
        switch SharingSetting(intent: intent) {
        case .manual, .inboundInquiry: return "Review Project"
        case .smartshare: return "Review & Share"
        }
    }

    var internalName: String {
        let name = form.companyBasics.internalName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled project" : name
    }

    /// `SELL_INTENT_STATUS_OPTIONS[supplyState].label`, Draft by default.
    var statusLabel: String {
        context.supplyState == "auto_draft" ? "Autodraft"
            : (SupplyState(rawValue: context.supplyState).map(\.label) ?? "Draft")
    }

    /// The primary contact, when they haven't signed the Terms of Service —
    /// the backend silently refuses to share then.
    var unsignedPrimaryContact: AccountMember? {
        member(form.messaging.assignedToUser).flatMap { $0.isTosSigned ? nil : $0 }
    }

    // MARK: - Autosave

    /// `$isAutosaveEnabled`: not in market, and in a state the backend
    /// accepts autosaves for.
    var isAutosaveEnabled: Bool {
        !context.isInMarket && Self.autosaveEligibleStates.contains(context.supplyState)
    }

    var isAutosaving: Bool { autosaveStatus == .saving }

    var hasUnsavedChanges: Bool {
        isDirty && (!pendingPatch.isEmptyObject || form.documents.hasPendingOperations)
    }

    /// The partial patch an autosave would send right now.
    var pendingPatch: JSONValue {
        Self.autosavePatch(current: currentPayload, baseline: baseline,
                           financialsInvalid: validation.financialsMinMaxError)
    }

    private var currentPayload: JSONValue {
        form.payload(over: intent, context: context)
    }

    private func formDidChange() {
        guard !suppressAutosave, isAutosaveEnabled else { return }
        if isAutosaving {
            // Picked up by the follow-up once the request returns.
            changedDuringSave = true
            return
        }
        debounce?.cancel()
        debounce = Task { [weak self] in
            guard let self else { return }
            do { try await sleep(Self.autosaveDebounce) } catch { return }
            await performAutosave()
        }
    }

    /// Tapping the indicator — saves now rather than waiting out the debounce.
    func triggerAutosave() async {
        debounce?.cancel()
        await performAutosave()
    }

    /// Resolves once nothing is waiting to be saved: a pending debounce is
    /// run now and any in-flight save (and its follow-up) has finished. Close
    /// awaits this so leaving can't drop an edit. `awaitAutosaveSettled`.
    func settleAutosave() async {
        if let inFlight { await inFlight.value }
        if isAutosaveEnabled, hasUnsavedChanges {
            debounce?.cancel()
            await performAutosave()
        }
        if let inFlight { await inFlight.value }
    }

    /// Single-flight: a second call while one is running is a no-op, and the
    /// running one re-runs itself if the form moved underneath it.
    private func performAutosave() async {
        // An invalid KPI or URL never reaches the server; the next edit
        // retries once it's fixed.
        guard isAutosaveEnabled, !isAutosaving, !validation.blocksAutosave else { return }
        let task = Task { await runAutosave() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func runAutosave() async {
        while true {
            changedDuringSave = false
            let snapshot = currentPayload
            let patch = Self.autosavePatch(current: snapshot, baseline: baseline,
                                           financialsInvalid: validation.financialsMinMaxError)
            let documents = form.documents
            guard !patch.isEmptyObject || documents.hasPendingOperations else {
                // Nothing to send — `autosaveProject` short-circuits as a success.
                if hasStartedAutosave { autosaveStatus = .saved }
                isDirty = false
                return
            }

            hasStartedAutosave = true
            autosaveStatus = .saving
            do {
                if documents.hasPendingOperations {
                    try await Self.withRetry(sleep: sleep) { [self] in try await processDocuments() }
                }
                let response: AutosaveResponse = try await Self.withRetry(sleep: sleep) { [api, intentId] in
                    try await api.patch("intents/\(intentId)/sellside-autosave", body: patch)
                }
                // The baseline is what was sent, not the form now — an edit
                // made while the request was out stays in the next diff.
                baseline = snapshot
                intent = Self.merging(patch, into: intent)
                lastSavedAt = response.lastAutosaveSuccess ?? now()
                lastSaveError = nil
                autosaveStatus = .saved
                if !changedDuringSave { isDirty = false }
            } catch {
                lastSaveError = Self.message(for: error)
                autosaveStatus = .error
                // A failed save never queues a follow-up.
                changedDuringSave = false
                return
            }

            guard changedDuringSave, isAutosaveEnabled, !validation.blocksAutosave else { return }
        }
    }

    /// `processDocumentOperations`: deletions and uploads before the intent
    /// PATCH. Each operation is cleared as it succeeds, so a retry resumes
    /// rather than repeating, and a file picked mid-save waits for the next.
    private func processDocuments() async throws {
        let snapshot = form.documents
        for document in snapshot.deletionsToSend {
            if let id = document.serverID { try await api.delete("documents/\(id)") }
            withoutAutosave(rebaseline: false) { $0.documents.didSave(uploads: [], uploadedIDs: [:], deletions: [document]) }
        }
        for upload in snapshot.pendingUploads {
            var form = MultipartForm()
            if let file = upload.file {
                form.parts.append(.file(name: "file", filename: upload.filename, mimeType: upload.mimeType,
                                        data: file.data))
            } else {
                // The standard NDA: the backend makes it from an empty file.
                form.parts.append(.field(name: "file", value: ""))
            }
            form.parts.append(.field(name: "bucket", value: upload.bucket))
            form.parts.append(.field(name: "signature_type", value: upload.signatureType))
            let response: UploadedDocument = try await api.upload("documents/intent/\(intentId)", form: form)
            withoutAutosave(rebaseline: false) {
                $0.documents.didSave(uploads: [upload], uploadedIDs: [upload.localID: response.id], deletions: [])
            }
        }
        // Deletions skipped because the bucket's upload replaces them are
        // done with too.
        withoutAutosave(rebaseline: false) {
            $0.documents.didSave(uploads: [], uploadedIDs: [:], deletions: snapshot.pendingDeletions)
        }
    }

    // MARK: - Manual save

    /// The full save behind the review screen's CTAs — `saveProject`:
    /// documents, then `PATCH /intents/{id}` with the whole form-derived
    /// intent. Returns the server's intent, which becomes the new base.
    @discardableResult
    func save(overrides: [String: JSONValue] = [:]) async throws -> JSONValue {
        if let reason = ndaBlocksSave { throw SetupError.blocked(reason) }
        debounce?.cancel()
        if let inFlight { await inFlight.value }
        var payload = currentPayload
        for (key, value) in overrides { payload.set(value, at: key) }
        if form.documents.hasPendingOperations { try await processDocuments() }
        let response: PatchIntentResponse = try await api.patch("intents/\(intentId)", body: payload)
        intent = response.intent
        context = SetupContext(intent: response.intent, now: context.now, memberCount: context.memberCount)
        baseline = form.payload(over: intent, context: context)
        isDirty = false
        lastSavedAt = now()
        return response.intent
    }

    /// `isNdaMissingForInMarketIntent`: the backend rejects an in-market
    /// project with no NDA.
    var ndaBlocksSave: String? {
        guard context.isInMarket, form.nda.ndaType != "waive", form.documents.nda == nil,
              !form.documents.hasPendingUpload("NDA"), form.nda.linkedNdaUrl.isEmpty else { return nil }
        return "In-market projects require an NDA selection. Please update the NDA before saving."
    }

    enum ShareOutcome: Equatable {
        /// Live — the contacted list (SmartShare) or manual review.
        case shared(SmartShare: Bool)
        /// Saved, with sharing waiting on Axial's review.
        case submittedForApproval
        /// In market: saved in place.
        case saved
    }

    /// `handleShareFlow` and `saveProjectAndReturn`. Activation happens
    /// server-side when the intent says it can — the client never sets the
    /// supply state itself.
    func share(submitForApproval: Bool) async throws -> ShareOutcome {
        if context.isInMarket {
            try await save()
            return .saved
        }
        let smartShare = form.sharingSettings.sharingMode == "smartshare"
        var overrides: [String: JSONValue] = [:]
        if submitForApproval {
            overrides["approval_state"] = .string(smartShare ? "under_review" : "under_review_send_all")
        }
        let saved = try await save(overrides: overrides)
        if submitForApproval { return .submittedForApproval }
        if saved["available_actions"]?["can_activate"]?.bool == true {
            let activated: JSONValue = try await api.post("intents/sellside/\(intentId)/activate")
            intent = activated
            context = SetupContext(intent: activated, now: context.now, memberCount: context.memberCount)
        }
        return .shared(SmartShare: smartShare)
    }

    /// `needsApproval = !account.can_share_teasers`.
    var needsApproval: Bool { !context.account.canShareTeasers }

    /// `POST /intents/{id}/share-teaser-preview`.
    func sendTestMessage() async throws {
        let _: JSONValue = try await api.post("intents/\(intentId)/share-teaser-preview",
                                              body: ["message": JSONValue.string(form.messaging.teaserMessage)])
    }

    /// `POST /intents/{id}/refer` → the shareable link.
    func dealLink() async throws -> String {
        let response: JSONValue = try await api.post("intents/\(intentId)/refer", body: JSONValue.object([:]))
        guard let url = response["short_url"]?.string else { throw SetupError.blocked("Couldn't create a link.") }
        return url
    }

    /// The full payload, for the review screen's summary.
    var reviewPayload: JSONValue { currentPayload }

    /// What the review's Changes list diffs against.
    var savedPayload: JSONValue { baseline }

    // MARK: - Rules (static so they test without a session)

    /// `buildAutosavePayload`: diff against the baseline, then two
    /// invariants — financials that fail the min/max check are left out
    /// (manual save still sends them), and the two fields that together
    /// encode the sharing mode always travel as a pair.
    static func autosavePatch(current: JSONValue, baseline: JSONValue, financialsInvalid: Bool) -> JSONValue {
        var current = current
        if financialsInvalid, var company = current["company"]?.object {
            company["financials"] = nil
            current.set(.object(company), at: "company")
        }
        var patch = current.diff(from: baseline)
        let pair = ["use_smartshare", "requires_approval"]
        if pair.contains(where: { patch[$0] != nil }) {
            for key in pair {
                if let value = current[key] { patch.set(value, at: key) }
            }
        }
        return patch
    }

    /// `autosaveWithRetry$`: 5xx (or no status at all) retries after 2s, 4s
    /// and 8s; a 4xx is final.
    static func withRetry<T>(
        sleep: (Duration) async throws -> Void,
        _ operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard isRetryable(error), attempt < maxRetryAttempts else { throw error }
                attempt += 1
                try await sleep(.seconds(1 << attempt))
            }
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case APIError.server(let code, _, _): code >= 500
        case APIError.unauthorized, APIError.decoding, is SetupError: false
        default: true
        }
    }

    /// The web's growls: "Failed to autosave" for a 4xx, and the retry
    /// exhaustion message otherwise.
    static func message(for error: Error) -> String {
        if case APIError.server(let code, _, _) = error, (400..<500).contains(code) {
            return "Failed to autosave"
        }
        return "Failed to autosave after multiple attempts. Please try saving manually."
    }

    /// Folds a sent patch back into the base intent, recursing like the diff.
    static func merging(_ patch: JSONValue, into base: JSONValue) -> JSONValue {
        guard let patchObject = patch.object, var result = base.object else { return patch }
        for (key, value) in patchObject {
            if value.object != nil, let existing = result[key], existing.object != nil {
                result[key] = merging(value, into: existing)
            } else {
                result[key] = value
            }
        }
        return .object(result)
    }
}

enum SetupError: LocalizedError, Equatable {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let message): message
        }
    }
}

// MARK: - Responses

/// `ISellsideAutosaveResponse`.
struct AutosaveResponse: Decodable {
    let isComplete: Bool?
    let lastAutosaveSuccess: Date?

    enum CodingKeys: String, CodingKey {
        case isComplete = "is_complete"
        case lastAutosaveSuccess = "last_autosave_success"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isComplete = try? c.decodeIfPresent(Bool.self, forKey: .isComplete)
        lastAutosaveSuccess = EpochDate.decode(c, forKey: .lastAutosaveSuccess)
    }
}

/// `IPatchIntentResponse`.
struct PatchIntentResponse: Decodable {
    let intent: JSONValue
}

/// `IUploadedDocumentResponse`.
struct UploadedDocument: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? c.decode(String.self, forKey: .id) { id = text }
        else { id = String(try c.decode(Int.self, forKey: .id)) }
    }
}

extension SetupContext {
    init(intent: JSONValue, now: Date = .now, memberCount: Int = 0) {
        let account = intent["owned_by_account"]
        self.init(
            intentType: intent["intent_type"]?.string ?? "sell_business",
            supplyState: intent["supply_state"]?.string ?? "",
            intentState: intent["intent_state"]?.string ?? "",
            canManuallyShare: account?["can_manually_share"]?.bool,
            now: now,
            memberCount: memberCount,
            isShared: intent["is_shared"]?.bool ?? false,
            account: AccountFlags(
                canWaiveNDA: account?["can_waive_nda"]?.bool ?? false,
                canLinkNDA: account?["can_link_nda"]?.bool ?? false,
                canWaiveCIM: account?["can_waive_cim"]?.bool ?? false,
                canLinkCIM: account?["can_link_cim"]?.bool ?? false,
                requireEditableNDA: account?["require_editable_nda"]?.bool ?? false,
                canShareTeasers: account?["can_share_teasers"]?.bool ?? true,
                canUseAdvancedFilters: account?["can_use_advanced_filters"]?.bool ?? true,
                name: account?["name"]?.string
            )
        )
    }
}
