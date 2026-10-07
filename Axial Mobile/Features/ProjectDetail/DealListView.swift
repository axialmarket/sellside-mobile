//
//  DealListView.swift
//  Axial Mobile
//

import SwiftUI

/// What a member list shows: one whole section, or a dashboard drill-down.
enum DealListSource: Hashable {
    case bucket(SellsideDeal.Bucket)
    case segment(DealSegment)

    var title: String {
        switch self {
        case .bucket(let bucket): bucket.title
        case .segment(let segment): segment.title
        }
    }

    var emptyMessage: String {
        switch self {
        case .bucket(let bucket): bucket.emptyMessage
        case .segment(let segment): segment.emptyMessage
        }
    }

    func deals(in dashboard: ProjectDashboard) -> [SellsideDeal] {
        switch self {
        case .bucket(let bucket): dashboard.deals(in: bucket)
        case .segment(let segment): segment.deals(in: dashboard)
        }
    }
}

/// One section of a project's members, as its own screen.
///
/// Pushed rather than switched, so the section gets a full-width title, its
/// own scroll position and room for its own toolbar later. It also owns the
/// deal actions, because this is the only place deals are listed.
struct DealListView: View {
    let projectId: String
    let source: DealListSource

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(ProjectsStore.self) private var projectsStore

    @State private var endingDiscussionsWith: SellsideDeal?
    @State private var actionError: String?

    private var dashboard: ProjectDashboard? {
        store.dashboard(for: projectId)
    }

    /// Which project these members belong to. Two screens deep, the title
    /// says "Contacted" and nothing else would say contacted *to what* —
    /// so it rides along as the navigation subtitle.
    ///
    /// Fetched project first, then the list row we already hold, so it's
    /// there before this screen's own load resolves.
    private var projectName: String? {
        dashboard?.project.internalName
            ?? projectsStore.project(withIntentId: projectId)?.internalName
    }

    var body: some View {
        ScrollView {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(AxialColor.layer2)
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(projectName ?? "")
        .refreshable {
            if await store.load(id: projectId) {
                Haptics.success()
            } else {
                Haptics.error()
            }
        }
        // Normally warm — you arrive here from the project screen — but a
        // cold cache (restored state, a future deep link) still resolves.
        .task { await store.loadIfNeeded(id: projectId) }
        .confirmationDialog(
            "End Discussions",
            isPresented: endDiscussionsBinding,
            titleVisibility: .visible,
            presenting: endingDiscussionsWith
        ) { deal in
            Button("End Discussions", role: .destructive) {
                mark(deal, as: .endedDiscussions)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deal in
            Text("You're about to end discussions with \(deal.displayName).")
        }
        .alert(
            "Couldn't update this member",
            isPresented: errorBinding,
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let dashboard {
            DealList(
                deals: source.deals(in: dashboard),
                busyDealIds: store.updatingDealIds,
                emptyMessage: source.emptyMessage,
                onAction: handle
            )
        } else {
            DealListSkeleton()
        }
    }

    private func handle(_ deal: SellsideDeal, _ request: DealActionRequest) {
        switch request {
        case .updateStatus:
            // Web updates a single row straight from its menu; only the bulk
            // path confirms first.
            mark(deal, as: request.status)
        case .endDiscussions:
            endingDiscussionsWith = deal
        }
    }

    private func mark(_ deal: SellsideDeal, as status: DealStatus) {
        Task {
            do {
                try await store.markDeals([deal.id], as: status, on: projectId)
                Haptics.success()
            } catch {
                Haptics.error()
                actionError = error.localizedDescription
            }
        }
    }

    private var endDiscussionsBinding: Binding<Bool> {
        Binding(
            get: { endingDiscussionsWith != nil },
            set: { if !$0 { endingDiscussionsWith = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }
}
