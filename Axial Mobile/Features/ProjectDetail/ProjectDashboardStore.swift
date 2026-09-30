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
        updatingDealIds.formUnion(dealIds)
        defer { updatingDealIds.subtract(dealIds) }

        let updates: [DealStatusUpdate] = try await apiClient.post(
            "deals/supply-marking-status",
            body: MarkDealsRequest(status: status.rawValue, publicIds: dealIds)
        )
        apply(updates, on: projectId)
    }

    func isUpdating(dealId: String) -> Bool {
        updatingDealIds.contains(dealId)
    }

    /// Entry point for a deal-status response. Sibling of `apply(_:)` — same
    /// rule, different endpoint: the mutation's own response is the update.
    func apply(_ updates: [DealStatusUpdate], on projectId: String) {
        guard case .loaded(let dashboard) = state(for: projectId) else { return }
        states[projectId] = .loaded(dashboard.applying(updates))
    }

    /// Entry point for any response carrying a whole project — see the type
    /// comment. Keep mutation responses coming through here.
    ///
    /// The deals we already hold are kept: the status endpoints return the
    /// intent alone, and none of them changes who's been contacted.
    func apply(_ project: ProjectDetail) {
        if case .loaded(let dashboard) = state(for: project.id) {
            states[project.id] = .loaded(dashboard.replacingProject(project))
        }
        projectsStore.apply(project)
    }

    private func fetch(id: String) async -> Bool {
        let isCold = dashboard(for: id) == nil
        if isCold { states[id] = .loading }

        do {
            // Concurrent, but both must land before the screen is usable: the
            // status actions depend on the deals, and so does the tab bar.
            async let project: ProjectDetail = apiClient.get("intents/\(id)")
            async let deals: [SellsideDeal] = apiClient.get("intents/sellside/\(id)/deals")
            let dashboard = try await ProjectDashboard(project: project, deals: deals)

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
