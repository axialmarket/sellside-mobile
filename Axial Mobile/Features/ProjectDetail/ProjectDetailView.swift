//
//  ProjectDetailView.swift
//  Axial Mobile
//

import SwiftUI

/// Mobile equivalent of the web's sell container. Owns the load states, the
/// toolbar and the project-level action flow; `ProjectDashboardView` owns
/// everything once the data has landed, and each member list is its own
/// pushed screen (`DealListView`).
struct ProjectDetailView: View {
    let projectId: String
    /// Set when the push came from a project card, so the screen can zoom out
    /// of — and be dragged back into — the row that opened it. Nil for a deep
    /// link, which has no source on screen to grow from.
    var transitionNamespace: Namespace.ID?

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(ProjectsStore.self) private var projectsStore
    @Environment(AuthenticationService.self) private var authService

    /// A status change on its way through `projectStatusFlow`.
    @State private var statusRequest: ProjectStatusRequest?
    @State private var performingId: String?
    /// The action item sheet that's up, if any.
    @State private var resolving: ProjectActionItem.ResolveSheet?
    /// A bulk action item's request, carried out by `dealResolver`.
    @State private var dealResolution: DealResolution?
    /// Action item sheets grow out of the button that opened them.
    @Namespace private var actionTransition

    private var loadState: ProjectDashboardStore.LoadState {
        store.state(for: projectId)
    }

    private var dashboard: ProjectDashboard? {
        store.dashboard(for: projectId)
    }

    /// Fetched project first — it's authoritative — then the list row.
    private var summary: ProjectSummary? {
        if let dashboard {
            return ProjectSummary(dashboard.project)
        }
        return projectsStore.project(withIntentId: projectId).map(ProjectSummary.init)
    }

    var body: some View {
        content
            .zoomingFrom(projectId, in: transitionNamespace)
            .background(AxialColor.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Both trailing controls override the stack's brand tint:
                // the list tints for the back chevron, but a bar control that
                // acts on the screen is chrome, not a link.
                ToolbarItem(placement: .topBarTrailing) { copyDealLinkButton }
                // Splits the trailing items into their own glass capsules;
                // without it iOS 26 pools adjacent bar items into one.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { actionsMenu }
            }
            .task { await store.loadIfNeeded(id: projectId) }
            .onChange(of: loadState) { _, newState in
                if newState == .unauthorized {
                    authService.expireSession()
                }
            }
            .projectStatusFlow($statusRequest, performingId: $performingId)
            .dealResolver(projectId: projectId, request: $dealResolution,
                          zoom: (actionTransition, { resolution in
                              ActionItemsCard.sourceID(resolution.kind == "shareCim" ? .sendCimToAll : .approveAll)
                          }))
            // Each resolve sheet saves through the store, so the dashboard
            // (and the action item) updates from the save's own response.
            .sheet(item: $resolving) { sheet in
                Group {
                    switch sheet {
                    case .uploadCim: UploadCIMSheet(projectId: projectId)
                    case .followUp: FollowUpSheet(projectId: projectId)
                    case .staleFinancials:
                        StaleFinancialsSheet(projectId: projectId)
                            .presentationDetents([.large])
                    }
                }
                .zooming(from: ZoomSource(namespace: actionTransition, id: ActionItemsCard.sourceID(sheet)))
            }
    }

    // MARK: - Content

    /// One tree for every state that has something to show.
    ///
    /// The earlier version switched on `loadState`, which put loading and
    /// loaded in different `@ViewBuilder` branches — so when the fetch landed
    /// SwiftUI tore down the scroll view, the header and the toolbar's
    /// surroundings and built them again. That's the blink. Now the structure
    /// is fixed and only the data inside it changes; the one genuine swap
    /// (skeleton to pipeline cards) cross-fades on its own.
    @ViewBuilder
    private var content: some View {
        if loadState == .unauthorized {
            Color.clear // expireSession() routes back to sign-in
        } else if case .failed(let message) = loadState, summary == nil {
            // Nothing borrowed and nothing fetched: the whole screen is the
            // error. This is the only state with a different shape.
            coldFailureView(message)
        } else {
            scrollingStack {
                ProjectDashboardView(
                    projectId: projectId,
                    summary: summary,
                    dashboard: dashboard,
                    isLoading: loadState == .loading,
                    isPerforming: isPerforming,
                    onStatusAction: handle,
                    onResolve: { resolving = $0 },
                    transitionNamespace: actionTransition,
                    onBulk: { action, deals in
                        switch action {
                        case .approveAll: dealResolution = .accept(deals)
                        case .sendCimToAll: dealResolution = .shareCim(deals)
                        }
                    },
                    busyDealIds: store.updatingDealIds
                )

                if case .failed(let message) = loadState {
                    errorBanner(message)
                }
            }
        }
    }

    private func coldFailureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load this project", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await store.load(id: projectId) } }
                .buttonStyle(.glassProminent)
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
            Button("Retry") { Task { await store.load(id: projectId) } }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 16)
    }

    private func scrollingStack<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Without this there's nothing to pull against before content lands.
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable {
            if await store.load(id: projectId) {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
    }

    // MARK: - Toolbar

    private var copyDealLinkButton: some View {
        Button {
            copyDealLink()
        } label: {
            Label("Copy Deal Link", systemImage: "link")
        }
        .labelStyle(.iconOnly)
        // Web greys this out until the project is complete — nothing worth
        // linking to before then.
        .disabled(dashboard?.project.canCopyDealLink != true)
        .tint(AxialColor.textPrimary)
        .accessibilityIdentifier("copy-deal-link")
    }

    private var actionsMenu: some View {
        ProjectActionsMenu(
            menu: dashboard.map { ManageProjectMenu(project: $0.project) },
            isPerforming: isPerforming,
            onSelect: handle
        )
        .tint(AxialColor.textPrimary)
    }

    private func handle(_ action: ProjectAction) {
        statusRequest = ProjectStatusRequest(projectId: projectId, action: action)
    }

    private func copyDealLink() {
        // Web's own handler is still a console log
        // (project-setup-header.component.ts) — nothing to mirror yet.
        Haptics.lightImpact()
        print("TODO: copy deal link for \(projectId)")
    }

    private var isPerforming: Bool {
        performingId == projectId
    }
}

extension View {
    /// Applies the zoom transition only when there's a source to zoom from.
    /// Without a namespace this is the plain push, which is what a deep link
    /// should get.
    ///
    /// Under Reduce Motion the system swaps the zoom for a cross-fade on its
    /// own — nothing to gate here, and gating it ourselves would only break
    /// the pairing.
    @ViewBuilder
    func zoomingFrom(_ sourceID: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
