//
//  ProjectDashboardStore.swift
//  Axial Mobile
//

import Foundation
import Observation

/// Single source of truth for loaded project dashboards.
///
/// App-scoped and keyed by intent id, so reopening a project you've already
/// visited renders from cache — only a genuinely cold project costs a fetch.
///
/// A dashboard is the project *and* its deals, fetched concurrently and
/// resolved together: the status actions can't be offered safely until both
/// are in hand, and the tabs are derived from the deals (see
/// `ProjectDashboard`). Either request failing fails the load.
///
/// Every response carrying a whole project flows through `apply(_:)` — the
/// initial GET, and each status action, all of which answer with the intent.
/// That's the pattern: a mutation updates local state from its own response,
/// so nothing re-GETs, and the projects list is patched at the same time so
/// its card can't drift from the dashboard.
@Observable
final class ProjectDashboardStore {
    enum LoadState: Equatable {
        case loading
        case loaded(ProjectDashboard)
        case failed(String)
        case unauthorized
    }

    private(set) var states: [String: LoadState] = [:]
    /// Deals with a status change in flight.
    private(set) var updatingDealIds: Set<String> = []
    /// How many requests are in flight per deal, so overlapping requests on
    /// one deal don't clear its busy state early.
    private var busyCounts: [String: Int] = [:]
    /// Bumped by every mutation that patches local state. A fetch that
    /// started before a mutation would otherwise land on top of it and undo
    /// it — accept A, accept B a second later, and A's refresh puts B back.
    private var mutationCounts: [String: Int] = [:]

    private let apiClient: any APIRequesting
    private let projectsStore: ProjectsStore
    /// Collapses a pull-to-refresh that lands on top of the initial fetch.
    private var inFlight: [String: Task<Bool, Never>] = [:]

    init(apiClient: any APIRequesting, projectsStore: ProjectsStore) {
        self.apiClient = apiClient
        self.projectsStore = projectsStore
    }

    func state(for id: String) -> LoadState {
        states[id] ?? .loading
    }

    func dashboard(for id: String) -> ProjectDashboard? {
        guard case .loaded(let dashboard) = state(for: id) else { return nil }
        return dashboard
    }

    /// Cold load: fetches only when nothing is cached for this project.
    func loadIfNeeded(id: String) async {
        guard dashboard(for: id) == nil else { return }
        await load(id: id)
    }

    /// Fetches unconditionally (pull-to-refresh, retry). Returns `false` on
    /// failure so the caller can react — a failed refresh leaves whatever was
    /// already on screen in place.
    @discardableResult
    func load(id: String) async -> Bool {
        if let existing = inFlight[id] { return await existing.value }
        let task = Task { await fetch(id: id) }
        inFlight[id] = task
        let succeeded = await task.value
        inFlight[id] = nil
        return succeeded
    }

    /// Runs a status action and folds the response back in. Throws so the view
    /// can report why it failed; local state is untouched on failure.
    func perform(
        _ action: ProjectAction,
        on id: String,
        counterparty: CounterpartyInfo? = nil
    ) async throws {
        let path = "intents/\(id)/\(action.path)"
        let updated: ProjectDetail
        if let counterparty {
            updated = try await apiClient.post(path, body: counterparty)
        } else {
            updated = try await apiClient.post(path)
        }
        apply(updated)
    }

    /// The project as raw JSON — what a resolve sheet edits over, so the
    /// keys it sends back carry every field mobile doesn't model.
    func rawProject(id: String) async throws -> JSONValue {
        try await apiClient.get("intents/\(id)")
    }

    /// Saves a handful of top-level intent keys — `PATCH /api/intents/{id}`,
    /// the call behind the web's Save Project — and folds the returned
    /// intent back in like any other mutation. Each resolve sheet sends only
    /// what it owns (whole objects for nested keys like `company`, never a
    /// partial one), so nothing else on the project can be disturbed.
    func updateProject(id: String, patch: JSONValue) async throws {
        let response: ProjectUpdateResponse = try await apiClient.patch("intents/\(id)", body: patch)
        apply(response.intent)
    }

    /// Uploads one document to the project — `POST /documents/intent/{id}`,
    /// multipart `file`, `bucket` (`T` / `NDA` / `OM`) and `signature_type`.
    func uploadDocument(to id: String, file: PickedFile, bucket: String,
                        signatureType: String = "download_only") async throws {
        var form = MultipartForm()
        form.parts.append(.file(name: "file", filename: file.filename, mimeType: file.mimeType, data: file.data))
        form.parts.append(.field(name: "bucket", value: bucket))
        form.parts.append(.field(name: "signature_type", value: signatureType))
        let _: JSONValue = try await apiClient.upload("documents/intent/\(id)", form: form)
    }

    /// Marks one or more deals with a new supply status —
    /// `POST /api/deals/supply-marking-status`, the same endpoint behind the
    /// web's Update Status and End Discussions.
    ///
    /// The response carries the changed deals, so it patches in place rather
    /// than re-fetching the list. Rows being changed are exposed through
    /// `isUpdating(dealId:)` so they can show as busy, mirroring the web's
    /// `updatingSellsideDealsIds`.
    func markDeals(
        _ dealIds: [String],
        as status: DealStatus,
        on projectId: String
    ) async throws {
        guard !dealIds.isEmpty else { return }
        beginBusy(dealIds)
        defer { endBusy(dealIds) }

        let updates: [DealStatusUpdate]
        if status == .endedDiscussions {
            updates = try await endDiscussions(dealIds)
        } else {
            updates = try await apiClient.post(
                "deals/supply-marking-status",
                body: MarkDealsRequest(status: status.rawValue, publicIds: dealIds)
            )
        }
        apply(updates, on: projectId)
        // The response moves `supply_status` only. The funnel's `progress`
        // and the project's `updated_at` (the stale nudge) come with a full
        // fetch, which is why the web refetches on returning to the
        // dashboard (`SellDashboardStore.onInit`).
        if refreshesAfterResolving { Task { await load(id: projectId) } }
    }

    /// Ending discussions has its own endpoint on the web now —
    /// `POST /deals/sellside/end-discussions` with `{ public_ids }`, which
    /// checks each deal's eligibility (`SellsideDealApiService.endDiscussions`).
    /// An API without it yet answers 404, and then the older route, marking
    /// `ended_discussions`, still does the job.
    private func endDiscussions(_ dealIds: [String]) async throws -> [DealStatusUpdate] {
        do {
            return try await apiClient.post("deals/sellside/end-discussions", body: PublicIDsRequest(publicIds: dealIds))
        } catch APIError.server(let code, _, _) where code == 404 {
            return try await apiClient.post(
                "deals/supply-marking-status",
                body: MarkDealsRequest(status: DealStatus.endedDiscussions.rawValue, publicIds: dealIds)
            )
        }
    }

    // MARK: - Resolving members

    /// Accepts access requests — `POST /deals/approve-access` with
    /// `{ deal_ids }`, the web's bulk path (a single accept goes the same
    /// way here). Returns the deals that came back, for the growl's wording.
    @discardableResult
    func approveAccess(_ dealIds: [String], on projectId: String) async throws -> [DealStatusUpdate] {
        try await resolveDeals(dealIds, on: projectId) {
            try await self.apiClient.post("deals/approve-access", body: DealIDsRequest(dealIds: dealIds))
        }
    }

    /// Passes on members — `POST /deals/reject-access`, the bulk endpoint
    /// both of the web's pass paths use.
    func rejectAccess(_ dealIds: [String], on projectId: String) async throws {
        try await resolveDeals(dealIds, on: projectId) {
            try await self.apiClient.post("deals/reject-access", body: DealIDsRequest(dealIds: dealIds))
        }
    }

    /// Passes on recommendations — `POST /deals/sellside/pass` with
    /// `{ public_ids }`, the endpoint the web's recommended list uses for one
    /// member or many (`SellsideDealApiService.passDeals`). Access requests
    /// pass through `rejectAccess` instead.
    func passRecommended(_ dealIds: [String], on projectId: String) async throws {
        try await resolveDeals(dealIds, on: projectId) {
            try await self.apiClient.post("deals/sellside/pass", body: PublicIDsRequest(publicIds: dealIds))
        }
    }

    /// Restarts discussions — `POST /deals/restart-discussions` with
    /// `{ public_ids }`. The server walks each ended deal back to the deepest
    /// stage it reached and answers with the resulting statuses
    /// (`SellsideDealApiService.restartDiscussions`). The web sends ended
    /// deals only, and so does this.
    func restartDiscussions(_ dealIds: [String], on projectId: String) async throws {
        try await resolveDeals(dealIds, on: projectId) {
            try await self.apiClient.post("deals/restart-discussions", body: PublicIDsRequest(publicIds: dealIds))
        }
    }

    /// Sends the CIM with a note — `POST /deals/send-cim`. Anyone the server
    /// leaves out of its response is marked sent, as the web does.
    func sendCim(_ request: SendCIMRequest, on projectId: String) async throws {
        try await resolveDeals(request.dealIds, on: projectId) {
            let updates: [DealStatusUpdate] = try await self.apiClient.post("deals/send-cim", body: request)
            let returned = Set(updates.map(\.id))
            return updates + request.dealIds.filter { !returned.contains($0) }
                .map { DealStatusUpdate(id: $0, supplyStatus: .sentCim, demandIsRead: nil) }
        }
    }

    /// Nudges members who haven't answered the teaser — `POST /deals/nudge`
    /// with `{ deal_public_ids, message }` (`DealApiService.sendFollowUp`).
    /// Answers with the deals, like the other bulk endpoints.
    func sendFollowUp(_ dealIds: [String], message: String, on projectId: String) async throws {
        try await resolveDeals(dealIds, on: projectId) {
            try await self.apiClient.post("deals/nudge", body: FollowUpRequest(dealPublicIds: dealIds, message: message))
        }
    }

    /// The Formable editor for a redlined NDA —
    /// `POST /documents/formable/deal/{id}/redline-request`.
    func redlineEditorURL(dealId: String) async throws -> URL {
        let response: JSONValue = try await apiClient.post("documents/formable/deal/\(dealId)/redline-request",
                                                           body: JSONValue.object([:]))
        guard let text = response["redlineUrl"]?.string, let url = URL(string: text) else {
            throw APIError.unknown
        }
        return url
    }

    /// After the editor saves: `POST /documents/deal/{id}/submit-redline`,
    /// polled every 2 s (20 tries) until the redline is no longer pending,
    /// then the members are reloaded — the response carries nothing else.
    func submitRedline(dealId: String, on projectId: String,
                       sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws {
        for attempt in 0..<20 {
            let response: JSONValue = try await apiClient.post("documents/deal/\(dealId)/submit-redline",
                                                               body: JSONValue.object([:]))
            if response["has_pending_nda_redline"]?.bool != true {
                await load(id: projectId)
                return
            }
            if attempt < 19 { try await sleep(.seconds(2)) }
        }
        throw RedlineError.stillPending
    }

    enum RedlineError: LocalizedError {
        case stillPending
        var errorDescription: String? {
            "We had an issue submitting your redline. Please refresh and try again."
        }
    }

    /// The owning account's members, for CC lists —
    /// `GET /accounts/{id}/members?is_active=false`.
    func accountMembers(for intent: JSONValue) async -> [AccountMember] {
        guard let accountID = intent["owned_by_account_public_id"]?.string
                ?? intent["owned_by_account"]?["id"]?.string else { return [] }
        return (try? await apiClient.get("accounts/\(accountID)/members",
                                         query: [URLQueryItem(name: "is_active", value: "false")],
                                         headers: [:])) ?? []
    }

    /// Refetch after a slim bulk response. Tests turn it off so the refresh
    /// can't race their assertions.
    var refreshesAfterResolving = true

    /// Marks the rows busy, applies the response, then refreshes in the
    /// background: these slim responses carry no `progress` or
    /// `has_target_pursued`, which is why the web refetches too.
    @discardableResult
    private func resolveDeals(
        _ dealIds: [String],
        on projectId: String,
        _ request: () async throws -> [DealStatusUpdate]
    ) async throws -> [DealStatusUpdate] {
        guard !dealIds.isEmpty else { return [] }
        beginBusy(dealIds)
        defer { endBusy(dealIds) }
        let updates = try await request()
        apply(updates, on: projectId)
        if refreshesAfterResolving { Task { await load(id: projectId) } }
        return updates
    }

    func isUpdating(dealId: String) -> Bool {
        updatingDealIds.contains(dealId)
    }

    private func beginBusy(_ dealIds: [String]) {
        for id in dealIds { busyCounts[id, default: 0] += 1 }
        updatingDealIds.formUnion(dealIds)
    }

    private func endBusy(_ dealIds: [String]) {
        for id in dealIds {
            let remaining = (busyCounts[id] ?? 1) - 1
            busyCounts[id] = remaining > 0 ? remaining : nil
            if remaining <= 0 { updatingDealIds.remove(id) }
        }
    }

    /// Entry point for a deal-status response. Sibling of `apply(_:)` — same
    /// rule, different endpoint: the mutation's own response is the update.
    func apply(_ updates: [DealStatusUpdate], on projectId: String) {
        guard case .loaded(let dashboard) = state(for: projectId) else { return }
        mutationCounts[projectId, default: 0] += 1
        states[projectId] = .loaded(dashboard.applying(updates))
    }

    /// Entry point for any response carrying a whole project — see the type
    /// comment. Keep mutation responses coming through here.
    ///
    /// The deals we already hold are kept: the status endpoints return the
    /// intent alone, and none of them changes who's been contacted.
    func apply(_ project: ProjectDetail) {
        if case .loaded(let dashboard) = state(for: project.id) {
            mutationCounts[project.id, default: 0] += 1
            states[project.id] = .loaded(dashboard.replacingProject(project))
        }
        projectsStore.apply(project)
    }

    /// `IPatchIntentResponse`: `{ intent, is_first_recommendation }`.
    private struct ProjectUpdateResponse: Decodable {
        let intent: ProjectDetail
    }

    /// Concurrent, but both must land before the screen is usable: the
    /// status actions depend on the deals, and so does the tab bar.
    private func requestDashboard(_ id: String) async throws -> ProjectDashboard {
        async let project: ProjectDetail = apiClient.get("intents/\(id)")
        async let deals: [SellsideDeal] = apiClient.get("intents/sellside/\(id)/deals")
        return try await ProjectDashboard(project: project, deals: deals)
    }

    private func fetch(id: String) async -> Bool {
        let isCold = dashboard(for: id) == nil
        if isCold { states[id] = .loading }

        do {
            var mutationsBefore = mutationCounts[id, default: 0]
            var dashboard = try await requestDashboard(id)
            // A mutation landed while this was in flight, so the response may
            // predate it. Ask again rather than undo it. Bounded, so a burst
            // of actions can't keep the refresh going forever.
            var attempt = 0
            while mutationCounts[id, default: 0] != mutationsBefore, attempt < 2 {
                attempt += 1
                mutationsBefore = mutationCounts[id, default: 0]
                dashboard = try await requestDashboard(id)
            }

            states[id] = .loaded(dashboard)
            projectsStore.apply(dashboard.project)
            return true
        } catch APIError.unauthorized {
            states[id] = .unauthorized
            return false
        } catch {
            // Only a cold failure gets an error screen; a failed refresh keeps
            // the cached dashboard visible.
            if isCold { states[id] = .failed(error.localizedDescription) }
            return false
        }
    }
}
