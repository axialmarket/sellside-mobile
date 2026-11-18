//
//  ProjectDetailView.swift
//  Axial Mobile
//

import SwiftUI
import UIKit

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
    /// Its confirmation, opening from the Manage Project menu or the action
    /// item that asked.
    @State private var statusConfirmation: Confirmation?
    @State private var performingId: String?
    /// The action item sheet that's up, if any.
    @State private var resolving: ProjectActionItem.ResolveSheet?
    /// A bulk action item's request, carried out by `dealResolver`.
    @State private var dealResolution: DealResolution?
    /// Action item sheets grow out of the button that opened them.
    @Namespace private var actionTransition
    /// Copy Deal Link: while the link is being made, the moment after it
    /// lands on the clipboard, and why it failed.
    @State private var isCopyingLink = false
    @State private var linkCopied = false
    @State private var linkError: String?

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
            .projectStatusFlow($statusRequest, performingId: $performingId, confirmation: $statusConfirmation)
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
            .alert(
                "Couldn't copy the deal link",
                isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } }),
                presenting: linkError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
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
                    onStatusAction: { handle($0, anchor: ProjectStatusRequest.actionItem) },
                    statusConfirmation: $statusConfirmation,
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
        .cardSurface()
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
            Label(linkCopied ? "Deal Link Copied" : "Copy Deal Link",
                  systemImage: linkCopied ? "checkmark" : "link")
                .contentTransition(.symbolEffect(.replace))
        }
        .labelStyle(.iconOnly)
        // The web hides this unless the project is active; a bar item that
        // comes and goes loses its glass, so here it's disabled instead.
        .disabled(dashboard?.project.canCopyDealLink != true || isCopyingLink)
        .tint(AxialColor.textPrimary)
        .accessibilityIdentifier("copy-deal-link")
    }

    private var actionsMenu: some View {
        ProjectActionsMenu(
            menu: dashboard.map { ManageProjectMenu(project: $0.project) },
            isPerforming: isPerforming,
            onSelect: { handle($0, anchor: ProjectStatusRequest.manageMenu) }
        )
        .tint(AxialColor.textPrimary)
        .confirmation($statusConfirmation, anchor: ProjectStatusRequest.manageMenu)
    }

    private func handle(_ action: ProjectAction, anchor: String) {
        statusRequest = ProjectStatusRequest(projectId: projectId, action: action, anchor: anchor)
    }

    /// Makes a fresh shareable link and puts it on the clipboard, as the
    /// web's `[axlCopy]="generateDealLink"` does (sell-header.component).
    /// The button turns into a tick for a moment — the web's "Deal Link
    /// Copied" label.
    private func copyDealLink() {
        isCopyingLink = true
        Task {
            do {
                UIPasteboard.general.string = try await store.dealLink(for: projectId)
                Haptics.success()
                AccessibilityNotification.Announcement("Deal link copied").post()
                linkCopied = true
                isCopyingLink = false
                try? await Task.sleep(for: .seconds(2))
                linkCopied = false
            } catch {
                Haptics.error()
                linkError = error.localizedDescription
                isCopyingLink = false
            }
        }
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
