//
//  ProjectDetailView.swift
//  Axial Mobile
//

import SwiftUI

/// Value pushed onto the projects navigation stack.
///
/// Deliberately just an id: everything the dashboard can show before its own
/// fetch returns is looked up from `ProjectsStore`, so the row stays live
/// rather than becoming a stale copy frozen into the navigation path. Deep
/// links build one of these directly and simply find nothing to borrow.
struct ProjectRoute: Hashable {
    let id: String

    init(id: String) {
        self.id = id
    }

    init(_ project: SellsideProject) {
        self.init(id: project.intentId)
    }
}

/// Mobile equivalent of the web's sell dashboard (`SellContainer`). Today
/// that's the header; tabs for recommended / contacted / interested members
/// come next.
///
/// The header renders from whatever we know first — the tapped list row, or
/// the fetched project once `GET /api/intents/{id}` lands. Only content the
/// list can't supply waits on that fetch, so tapping a card is friction-free
/// and skeletons are reserved for what's genuinely unknown.
struct ProjectDetailView: View {
    let route: ProjectRoute

    @Environment(ProjectDetailStore.self) private var store
    @Environment(ProjectsStore.self) private var projectsStore
    @Environment(AuthenticationService.self) private var authService

    private var loadState: ProjectDetailStore.LoadState {
        store.state(for: route.id)
    }

    /// Fetched project first — it's authoritative — then the list row.
    private var summary: ProjectSummary? {
        if let detail = store.detail(for: route.id) {
            return ProjectSummary(detail)
        }
        return projectsStore.project(withIntentId: route.id).map(ProjectSummary.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The dashboard is short enough not to overflow yet; without this
        // there's nothing to pull against.
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(AxialColor.layer2)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if await store.load(id: route.id) {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
        .task { await store.loadIfNeeded(id: route.id) }
        .onChange(of: loadState) { _, newState in
            if newState == .unauthorized {
                authService.expireSession()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading, .loaded:
            ProjectHeader(summary: summary)
            // Everything the list row can't supply belongs below here, each
            // piece skeletoned against `loadState` until the fetch lands.

        case .failed(let message):
            // A borrowed header is still worth showing; only a cold failure
            // leaves us with nothing to put on screen.
            if let summary {
                ProjectHeader(summary: summary)
                errorBanner(message)
            } else {
                errorView(message)
            }

        case .unauthorized:
            Color.clear // expireSession() routes back to sign-in
        }
    }

    /// Inline failure, used when the header already rendered from the list row.
    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't load the rest of this project", systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AxialColor.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(AxialColor.textSecondary)
            Button("Retry") {
                Task { await store.load(id: route.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AxialColor.border))
    }

    /// Cold failure — nothing was borrowed, so the whole screen is the error.
    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load this project", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await store.load(id: route.id) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }
}
