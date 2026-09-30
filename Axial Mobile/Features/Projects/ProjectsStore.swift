//
//  ProjectsStore.swift
//  Axial Mobile
//

import Foundation
import Observation

/// Owns the projects list state. Views render `state`/`sections` and call `load()`.
@Observable
final class ProjectsStore {
    enum LoadState: Equatable {
        case loading
        case loaded([SellsideProject])
        case empty
        case failed(String)
        case unauthorized
    }

    private(set) var state: LoadState = .loading
    private let apiClient: any APIRequesting

    init(apiClient: any APIRequesting) {
        self.apiClient = apiClient
    }

    /// Projects grouped by status in mobile section order; empty sections omitted.
    var sections: [(state: SupplyState, projects: [SellsideProject])] {
        guard case .loaded(let projects) = state else { return [] }
        return Self.grouped(projects)
    }

    static func grouped(_ projects: [SellsideProject]) -> [(state: SupplyState, projects: [SellsideProject])] {
        let byState = Dictionary(grouping: projects, by: \.supplyState)
        return SupplyState.sectionOrder.compactMap { state in
            guard let group = byState[state] else { return nil }
            let sorted = group.sorted {
                $0.internalName.localizedCaseInsensitiveCompare($1.internalName) == .orderedAscending
            }
            return (state, sorted)
        }
    }

    /// The row we already hold for a project, if the list has loaded — what
    /// the dashboard borrows so its header can render before its own fetch
    /// returns. Nil on a cold open (deep link, or the list never loaded).
    func project(withIntentId id: String) -> SellsideProject? {
        guard case .loaded(let projects) = state else { return nil }
        return projects.first { $0.intentId == id }
    }

    /// Folds a whole-project response back into the list so an edit made on
    /// the dashboard shows up here without re-fetching the list.
    func apply(_ detail: ProjectDetail) {
        guard case .loaded(let projects) = state else { return }
        let updated = Self.applying(detail, to: projects)
        guard updated != projects else { return }
        state = .loaded(updated)
    }

    static func applying(
        _ detail: ProjectDetail, to projects: [SellsideProject]
    ) -> [SellsideProject] {
        guard let index = projects.firstIndex(where: { $0.intentId == detail.id }) else {
            return projects
        }
        var updated = projects
        updated[index] = projects[index].merging(detail)
        return updated
    }

    /// Loads (or refreshes) the list. Keeps showing stale cards during a
    /// pull-to-refresh instead of flashing back to skeletons.
    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let projects: [SellsideProject] = try await apiClient.get("sellside-projects")
            state = projects.isEmpty ? .empty : .loaded(projects)
        } catch APIError.unauthorized {
            state = .unauthorized
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
