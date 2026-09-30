//
//  ProjectDetailStore.swift
//  Axial Mobile
//

import Foundation
import Observation

/// Single source of truth for whole project objects (`GET /api/intents/{id}`).
///
/// App-scoped and keyed by intent id, so reopening a project you've already
/// visited renders from cache — only a genuinely cold project costs a fetch.
///
/// Every response that carries a whole project flows through `apply(_:)`:
/// the initial GET today, and later `PATCH /api/intents/{id}` and the
/// status-change POSTs, which all answer with the full object. That's the
/// pattern — a save updates local state from its own response, so no
/// follow-up GET is needed, and the projects list is patched at the same
/// time so its card can't drift from the dashboard.
@Observable
final class ProjectDetailStore {
    enum LoadState: Equatable {
        case loading
        case loaded(ProjectDetail)
        case failed(String)
        case unauthorized
    }

    private(set) var states: [String: LoadState] = [:]

    private let apiClient: APIClient
    private let projectsStore: ProjectsStore
    /// Collapses a pull-to-refresh that lands on top of the initial fetch.
    private var inFlight: [String: Task<Bool, Never>] = [:]

    init(apiClient: APIClient, projectsStore: ProjectsStore) {
        self.apiClient = apiClient
        self.projectsStore = projectsStore
    }

    func state(for id: String) -> LoadState {
        states[id] ?? .loading
    }

    func detail(for id: String) -> ProjectDetail? {
        guard case .loaded(let detail) = state(for: id) else { return nil }
        return detail
    }

    /// Cold load: fetches only when nothing is cached for this project.
    func loadIfNeeded(id: String) async {
        guard detail(for: id) == nil else { return }
        await load(id: id)
    }

    /// Fetches unconditionally (pull-to-refresh, retry). Returns `false` on
    /// failure so the caller can react — a failed refresh leaves whatever
    /// was already on screen in place.
    @discardableResult
    func load(id: String) async -> Bool {
        if let existing = inFlight[id] { return await existing.value }
        let task = Task { await fetch(id: id) }
        inFlight[id] = task
        let succeeded = await task.value
        inFlight[id] = nil
        return succeeded
    }

    /// Entry point for any response carrying a whole project — see the type
    /// comment. Keep mutation responses coming through here.
    func apply(_ detail: ProjectDetail) {
        states[detail.id] = .loaded(detail)
        projectsStore.apply(detail)
    }

    private func fetch(id: String) async -> Bool {
        let isCold = detail(for: id) == nil
        if isCold { states[id] = .loading }

        do {
            let detail: ProjectDetail = try await apiClient.get("intents/\(id)")
            apply(detail)
            return true
        } catch APIError.unauthorized {
            states[id] = .unauthorized
            return false
        } catch {
            // Only a cold failure gets an error screen; a failed refresh keeps
            // the cached project visible.
            if isCold { states[id] = .failed(error.localizedDescription) }
            return false
        }
    }
}
