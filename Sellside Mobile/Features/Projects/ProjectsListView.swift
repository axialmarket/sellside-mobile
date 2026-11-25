//
//  ProjectsListView.swift
//  Sellside Mobile
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
    /// The project whose swiped Status sheet is up.
    @State private var statusSheetProject: SellsideProject?
    /// A status picked in that sheet, run once it has closed.
    @State private var pendingStatus: ProjectStatusRequest?
    /// A picked status change, carried through by `projectStatusFlow`.
    @State private var statusRequest: ProjectStatusRequest?
    /// Its confirmation, opening from the project's card.
    @State private var statusConfirmation: Confirmation?
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
        .projectStatusFlow($statusRequest, performingId: $updatingProjectId, confirmation: $statusConfirmation)
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
        case .offNetwork:
            OffNetworkView { await store.load() }
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
                        // A status change's confirmation opens from the card.
                        .confirmation($statusConfirmation, anchor: Confirmation.card(project.intentId))
                        .accessibilityIdentifier("project-card-\(project.intentId)")
                        // Long press lifts the card with its status changes,
                        // the same items as the dashboard's Update Project
                        // Status menu. Empty for a state with no transitions,
                        // which leaves the card with no menu at all.
                        .contextMenu {
                            ProjectStatusMenuItems(groups: statusGroups(for: project), title: "Update Status") {
                                requestStatus($0, for: project)
                            }
                            // The member lists, as the leading swipe offers
                            // them: only those with anyone in them.
                            if !project.listsWithMembers.isEmpty {
                                Section("Members") {
                                    ForEach(project.listsWithMembers, id: \.bucket) { list in
                                        Button {
                                            openList(list.bucket, of: project)
                                        } label: {
                                            Label(list.bucket.title, systemImage: Self.listIcon(list.bucket))
                                            Text("\(list.count) member\(list.count == 1 ? "" : "s")")
                                        }
                                        .accessibilityIdentifier("project-menu-\(list.bucket.title.lowercased())")
                                    }
                                }
                            }
                        }
                        .contentShape(.contextMenuPreview,
                                      RoundedRectangle(cornerRadius: ProjectCard.cornerRadius))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !statusGroups(for: project).isEmpty {
                                Button {
                                    Haptics.lightImpact()
                                    statusSheetProject = project
                                } label: {
                                    Label("Status", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .tint(AxialColor.brandPrimary)
                                .accessibilityIdentifier("project-swipe-status")
                            }
                        }
                        // Swiping right opens a member list directly, for
                        // each list that has anyone in it.
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            ForEach(project.listsWithMembers, id: \.bucket) { list in
                                Button {
                                    Haptics.lightImpact()
                                    openList(list.bucket, of: project)
                                } label: {
                                    Label(list.bucket.title, systemImage: Self.listIcon(list.bucket))
                                }
                                .tint(Self.listTint(list.bucket))
                                .accessibilityLabel("Open \(list.bucket.title), \(list.count) member\(list.count == 1 ? "" : "s")")
                                .accessibilityIdentifier("project-swipe-\(list.bucket.title.lowercased())")
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
                        }
                        .accessibilityHint("Opens the project dashboard")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                } header: {
                    ListSectionHeader(title: section.state.label, count: section.projects.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // A swipe action can't hold a menu, so Status opens a sheet of the
        // same choices. What's picked runs once the sheet has gone.
        .sheet(item: $statusSheetProject, onDismiss: runPendingStatus) { project in
            ProjectStatusSheet(project: project) { action in
                pendingStatus = ProjectStatusRequest(projectId: project.intentId, action: action,
                                                     anchor: Confirmation.card(project.intentId))
            }
            .presentationDetents([.medium, .large])
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

    /// Pushes the dashboard and the list together, so Back from the list
    /// lands on the project rather than skipping past it.
    private func openList(_ bucket: SellsideDeal.Bucket, of project: SellsideProject) {
        path.append(contentsOf: [ProjectsRoute(project), .deals(projectId: project.intentId, bucket: bucket)])
    }

    private static func listIcon(_ bucket: SellsideDeal.Bucket) -> String {
        switch bucket {
        case .recommended: "sparkles"
        case .contacted: "paperplane"
        case .interested: "hand.thumbsup"
        }
    }

    /// One family, darkening along the funnel.
    private static func listTint(_ bucket: SellsideDeal.Bucket) -> Color {
        switch bucket {
        case .recommended: AxialColor.textSecondary
        case .contacted: AxialColor.brandPrimary
        case .interested: AxialColor.brandPressed
        }
    }

    private func statusGroups(for project: SellsideProject) -> [[ProjectAction]] {
        ProjectAction.menu(for: project.supplyState)
    }

    private func requestStatus(_ action: ProjectAction, for project: SellsideProject) {
        statusRequest = ProjectStatusRequest(projectId: project.intentId, action: action,
                                             anchor: Confirmation.card(project.intentId))
    }

    /// Changes only when a project changes status, so search and filtering
    /// don't pick up the animation.
    private var statusSignature: [String] {
        store.projects.map { "\($0.publicId):\($0.supplyState.rawValue)" }
    }

    private func runPendingStatus() {
        guard let pending = pendingStatus else { return }
        pendingStatus = nil
        statusRequest = pending
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
