//
//  ProjectsListView.swift
//  Axial Mobile
//

import SwiftUI
import Auth0

struct ProjectsListView: View {
    @Environment(AuthenticationService.self) var authService
    @Environment(ProjectsStore.self) var store

    @State private var path: [ProjectsRoute] = []
    /// Ties each project card to the screen it opens, so the push grows out
    /// of the card instead of sliding over it.
    @Namespace private var projectTransition

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Projects")
                .background(AxialColor.layer2)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { profileMenu }
                }
                .navigationDestination(for: ProjectsRoute.self) { route in
                    switch route {
                    case .project(let id):
                        ProjectDetailView(projectId: id, transitionNamespace: projectTransition)
                    case .deals(let projectId, let bucket):
                        DealListView(projectId: projectId, bucket: bucket)
                    }
                }
        }
        .tint(AxialColor.brandPrimary)
        .task { await store.load() }
        .onChange(of: store.state) { _, newState in
            if newState == .unauthorized {
                authService.expireSession()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            skeleton
        case .loaded:
            projectList
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
            ForEach(store.sections, id: \.state) { section in
                Section {
                    ForEach(section.projects) { project in
                        Button {
                            // Push first; the dashboard loads behind the transition.
                            Haptics.lightImpact()
                            path.append(ProjectsRoute(project))
                        } label: {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(CardButtonStyle())
                        .matchedTransitionSource(id: project.intentId, in: projectTransition)
                        .accessibilityHint("Opens the project dashboard")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    sectionHeader(section.state, count: section.projects.count)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .topEdgeBackingForPinnedHeaders()
        .refreshable {
            await store.load()
            Haptics.success()
        }
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
        .background(AxialColor.layer2)
    }

    private var skeleton: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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

    private var profileMenu: some View {
        Menu {
            Section(profileMenuTitle) {
                Button(role: .destructive) {
                    Task { await authService.logout() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AxialColor.brandPrimary, in: Circle())
        }
        .accessibilityLabel("Profile")
    }

    private var profileMenuTitle: String {
        authService.user?.name ?? authService.user?.email ?? "Account"
    }

    private var initials: String {
        let name = authService.user?.name ?? ""
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "A" : String(letters).uppercased()
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
