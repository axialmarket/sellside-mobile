//
//  ProjectsListView.swift
//  Axial Mobile
//

import SwiftUI
import Auth0

struct ProjectsListView: View {
    @Environment(AuthenticationService.self) var authService
    @Environment(ProjectsStore.self) var store
    @Environment(AccountPresenter.self) var accountPresenter

    /// Owned by `ContentView`, which presents the Account sheet, so the
    /// sheet can zoom out of this screen's avatar.
    let accountTransition: Namespace.ID

    @State private var path: [ProjectsRoute] = []
    @State private var searchText = ""
    @State private var isFilterPresented = false
    @State private var filter = ProjectFilter()
    /// The project whose swipe action is asking which status to move to.
    @State private var statusPickerProject: SellsideProject?
    /// A picked status change, carried through by `projectStatusFlow`.
    @State private var statusRequest: ProjectStatusRequest?
    @State private var updatingProjectId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ties each project card to the screen it opens, so the push grows out
    /// of the card instead of sliding over it.
    @Namespace private var projectTransition
    /// Same idea for the bottom toolbar: the filter button is the source its
    /// sheet grows out of.
    @Namespace private var sheetTransition
    private static let filterTransitionID = "filter"

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Projects")
                .background(AxialColor.canvas)
                .toolbar {
                    // The avatar is its own background, so it opts out of
                    // the bar's glass — otherwise the bar sizes it like an
                    // icon button and wraps a capsule around the circle.
                    ToolbarItem(placement: .topBarTrailing) { accountButton }
                        .sharedBackgroundVisibility(.hidden)
                        .matchedTransitionSource(id: AccountPresenter.transitionID, in: accountTransition)
                }
                .searchable(text: $searchText, prompt: "Search projects")
                .toolbar { bottomBar }
                .sheet(isPresented: $isFilterPresented) {
                    ProjectFilterSheet(
                        filter: $filter,
                        projects: store.projects,
                        matchingCount: sections.reduce(0) { $0 + $1.projects.count }
                    )
                    .navigationTransition(.zoom(sourceID: Self.filterTransitionID, in: sheetTransition))
                }
                .navigationDestination(for: ProjectsRoute.self) { route in
                    switch route {
                    case .project(let id):
                        ProjectDetailView(projectId: id, transitionNamespace: projectTransition)
                    case .deals(let projectId, let bucket, let filter):
                        DealListView(projectId: projectId, source: .bucket(bucket), filter: filter)
                    case .segment(let projectId, let segment):
                        DealListView(projectId: projectId, source: .segment(segment))
                    }
                }
        }
        .tint(AxialColor.brandPrimary)
        .projectStatusFlow($statusRequest, performingId: $updatingProjectId)
        .task { await store.load() }
        .onChange(of: store.state) { _, newState in
            if newState == .unauthorized {
                authService.expireSession()
            }
        }
    }

    private var sections: [(state: SupplyState, projects: [SellsideProject])] {
        store.sections(matching: searchText, filter: filter)
    }

    /// Leading filter, then the system search field — the shape iOS 26 uses
    /// for a browsable list. `ToolbarSpacer` keeps the two in separate glass
    /// capsules instead of one pooled run. Mobile doesn't create projects, so
    /// there's no trailing add (CLAUDE.md, "Mobile resolves; the web edits").
    @ToolbarContentBuilder
    private var bottomBar: some ToolbarContent {
        // The transition source goes on the *item*, not the button inside it.
        // A bar item is bridged to UIKit, so a `View`-level source never
        // registers and the sheet just fades in. iOS 26 added the
        // `ToolbarContent` overload for exactly this.
        ToolbarItem(placement: .bottomBar) { filterButton }
            .matchedTransitionSource(id: Self.filterTransitionID, in: sheetTransition)
        ToolbarSpacer(.fixed, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
    }

    private var filterButton: some View {
        FilterToolbarButton(activeCount: filter.activeCount, identifier: "projects-filter-button") {
            isFilterPresented = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            skeleton
        case .loaded:
            if sections.isEmpty, filter.isActive {
                filteredEmpty
            } else if sections.isEmpty {
                // Loaded, but the query matched nothing — distinct from an
                // account with no projects at all.
                ContentUnavailableView.search(text: searchText)
            } else {
                projectList
            }
        case .empty:
            ContentUnavailableView(
                "No projects yet",
                systemImage: "folder",
                description: Text("Your sellside projects will appear here.")
            )
        case .failed(let message):
            errorView(message)
        case .unauthorized:
            Color.clear // expireSession() routes back to sign-in
        }
    }

    private var projectList: some View {
        List {
            ForEach(sections, id: \.state) { section in
                Section {
                    ForEach(section.projects) { project in
                        Button {
                            // Push first; the dashboard loads behind the transition.
                            Haptics.lightImpact()
                            path.append(ProjectsRoute(project))
                        } label: {
                            ProjectCard(project: project, isUpdating: updatingProjectId == project.intentId)
                        }
                        .buttonStyle(CardButtonStyle())
                        // Long press lifts the card with its status changes,
                        // the same items as the dashboard's Update Project
                        // Status menu. Empty for a state with no transitions,
                        // which leaves the card with no menu at all.
                        .contextMenu {
                            ProjectStatusMenuItems(groups: statusGroups(for: project), title: "Update Status") {
                                requestStatus($0, for: project)
                            }
                        }
                        .contentShape(.contextMenuPreview,
                                      RoundedRectangle(cornerRadius: ProjectCard.cornerRadius))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !statusGroups(for: project).isEmpty {
                                Button {
                                    Haptics.lightImpact()
                                    statusPickerProject = project
                                } label: {
                                    Label("Status", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .tint(AxialColor.brandPrimary)
                                .accessibilityIdentifier("project-swipe-status")
                            }
                        }
                        .disabled(updatingProjectId == project.intentId)
                        // Describe the card to the zoom transition, so it
                        // grows from the card's own shape instead of a shape
                        // the system infers. The SDK only accepts a
                        // RoundedRectangle clip and a Color background here —
                        // everything else is marked unavailable.
                        .matchedTransitionSource(id: project.intentId, in: projectTransition) {
                            $0.clipShape(.rect(cornerRadius: ProjectCard.cornerRadius))
                                .shadow(color: CardShadow.color, radius: CardShadow.radius, y: CardShadow.y)
                        }
                        .accessibilityHint("Opens the project dashboard")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                } header: {
                    sectionHeader(section.state, count: section.projects.count)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // A swipe action can't hold a menu, so it asks here instead — the
        // same choices, as an action sheet (Mail's More works the same way).
        .confirmationDialog(
            "Update Status",
            isPresented: statusPickerBinding,
            titleVisibility: .visible,
            presenting: statusPickerProject
        ) { project in
            ForEach(statusGroups(for: project).flatMap { $0 }) { action in
                Button(action.label) {
                    requestStatus(action, for: project)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(project.internalName)
        }
        // A status change moves the card to its new section; slide it there
        // rather than jumping.
        .animation(reduceMotion ? nil : .snappy, value: statusSignature)
        .topEdgeBackingForPinnedHeaders()
        .refreshable {
            await store.load()
            Haptics.success()
        }
    }

    private func statusGroups(for project: SellsideProject) -> [[ProjectAction]] {
        ProjectAction.menu(for: project.supplyState)
    }

    private func requestStatus(_ action: ProjectAction, for project: SellsideProject) {
        statusRequest = ProjectStatusRequest(projectId: project.intentId, action: action)
    }

    /// Changes only when a project changes status, so search and filtering
    /// don't pick up the animation.
    private var statusSignature: [String] {
        store.projects.map { "\($0.publicId):\($0.supplyState.rawValue)" }
    }

    private var statusPickerBinding: Binding<Bool> {
        Binding(get: { statusPickerProject != nil }, set: { if !$0 { statusPickerProject = nil } })
    }

    private func sectionHeader(_ state: SupplyState, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(state.label.uppercased())
            Text("\(count)")
                .foregroundStyle(AxialColor.textPlaceholder)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AxialColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AxialColor.canvas)
    }

    private var skeleton: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { _ in
                    ProjectCard(project: .mock(unread: nil))
                        .redacted(reason: .placeholder)
                        .shimmering()
                }
            }
            .padding(16)
        }
        .disabled(true)
    }

    /// Filters (and maybe a search) left nothing. Offer the way back out,
    /// since the filters themselves are a sheet away.
    private var filteredEmpty: some View {
        ContentUnavailableView {
            Label("No matching projects", systemImage: "line.3.horizontal.decrease")
        } description: {
            Text("Try removing a filter.")
        } actions: {
            Button("Clear Filters") {
                Haptics.selection()
                filter = ProjectFilter()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("projects-clear-filters")
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load projects", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await store.load() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Opens the Account sheet. The sheet itself lives in `ContentView`, so
    /// it can be raised from anywhere — this is just the usual way in.
    private var accountButton: some View {
        Button {
            Haptics.lightImpact()
            accountPresenter.present()
        } label: {
            UserAvatar(name: authService.user?.name, size: 36)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Account")
        .accessibilityIdentifier("projects-account-button")
    }
}

private extension View {
    /// iOS 26's default top edge is fully transparent, letting cards scroll
    /// visibly through the nav area above pinned section headers — force a
    /// hard edge there. iOS 27's default already backs the toolbar correctly
    /// (and its .hard variant shows the edge even at rest), so leave it alone.
    @ViewBuilder
    func topEdgeBackingForPinnedHeaders() -> some View {
        if #available(iOS 27.0, *) {
            self
        } else {
            self.scrollEdgeEffectStyle(.hard, for: .top)
        }
    }
}
