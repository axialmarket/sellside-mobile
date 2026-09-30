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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { actionsMenu } }
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

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loaded(let dashboard):
            scrollingStack { ProjectDashboardView(dashboard: dashboard) }

        case .loading:
            // The header renders from the borrowed list row; only what the
            // list can't supply waits on the fetch.
            scrollingStack {
                ProjectHeader(summary: summary)
                ProjectSectionLinksSkeleton()
            }

        case .failed(let message):
            failureView(message)

        case .unauthorized:
            Color.clear // expireSession() routes back to sign-in
        }
    }

    @ViewBuilder
    private func failureView(_ message: String) -> some View {
        // A borrowed header is still worth showing; only a cold failure leaves
        // us with nothing to put on screen.
        if let summary {
            scrollingStack {
                ProjectHeader(summary: summary)
                errorBanner(message)
            }
        } else {
            ContentUnavailableView {
                Label("Couldn't load this project", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await store.load(id: projectId) } }
                    .buttonStyle(.borderedProminent)
            }
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

    // MARK: - Actions

    @ViewBuilder
    private var actionsMenu: some View {
        if isPerforming {
            // The menu's own slot is where the wait belongs — it's the control
            // that was just used.
            ProgressView()
        } else if let summary {
            ProjectActionsMenu(
                supplyState: summary.supplyState,
                // Deals have to be in hand before a status change is offered.
                isEnabled: dashboard != nil
            ) { action in
                if action.needsCounterparty {
                    counterpartyAction = action
                } else {
                    confirmingAction = action
                }
            }
        }
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
