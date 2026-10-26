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

    @State private var confirmingAction: ProjectAction?
    @State private var counterpartyAction: ProjectAction?
    @State private var isPerforming = false
    @State private var actionError: String?
    /// Project setup is up — nil step opens the navigator.
    @State private var setupLaunch: SetupLaunch?

    struct SetupLaunch: Identifiable {
        let step: SetupStep?
        var id: String { step?.rawValue ?? "navigator" }
    }

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
            .background(AxialColor.layer2)
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
            .confirmationDialog(
                confirmingAction?.label ?? "",
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: confirmingAction
            ) { action in
                Button(action.label, role: action.isDestructive ? .destructive : nil) {
                    perform(action)
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(action.confirmationMessage)
            }
            .sheet(item: $counterpartyAction) { action in
                CounterpartySheet(
                    action: action,
                    options: dashboard?.counterpartyOptions ?? []
                ) { counterparty in
                    perform(action, counterparty: counterparty)
                }
            }
            // Full screen so it can't be swiped away — leaving goes through
            // setup's own close guard.
            .fullScreenCover(item: $setupLaunch) { launch in
                ProjectSetupView(projectId: projectId, initialStep: launch.step) { exit in
                    setupLaunch = nil
                    // Whatever happened in there, the dashboard is now stale.
                    Task { await store.load(id: projectId) }
                    if exit != .closed { Haptics.success() }
                }
            }
            .alert(
                "Couldn't update the project",
                isPresented: errorBinding,
                presenting: actionError
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
                    onStatusAction: { handle(.status($0)) },
                    onOpenSetup: { setupLaunch = SetupLaunch(step: $0) }
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
                .buttonStyle(.borderedProminent)
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
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AxialColor.border))
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

    private func handle(_ action: ProjectMenuAction) {
        switch action {
        case .status(let status):
            if status.needsCounterparty {
                counterpartyAction = status
            } else {
                confirmingAction = status
            }
        case .sharingSettings:
            // Web opens a modal here; mobile has no equivalent surface yet.
            print("TODO: sharing settings for \(projectId)")
        case .editProject:
            setupLaunch = SetupLaunch(step: nil)
        }
    }

    private func copyDealLink() {
        // Web's own handler is still a console log
        // (project-setup-header.component.ts) — nothing to mirror yet.
        Haptics.lightImpact()
        print("TODO: copy deal link for \(projectId)")
    }

    private func perform(_ action: ProjectAction, counterparty: CounterpartyInfo? = nil) {
        isPerforming = true
        Task {
            do {
                try await store.perform(action, on: projectId, counterparty: counterparty)
                Haptics.success()
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
            isPerforming = false
        }
    }

    // MARK: - Presentation bindings

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmingAction != nil }, set: { if !$0 { confirmingAction = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }
}

private extension View {
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
