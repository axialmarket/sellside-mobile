//
//  ProjectDashboardView.swift
//  Axial Mobile
//

import SwiftUI

/// A project's root screen: who it is, where it stands, what to do next, and
/// the way into its member lists.
///
/// Takes the project as an *optional* rather than being swapped in once it
/// loads. The header renders from the borrowed list row immediately, so the
/// screen is already correct before the fetch returns — and branching on the
/// load state out in the parent would rebuild this whole tree when it
/// resolves, which reads as a blink. Only the cards that depend on the deals
/// actually change, so only they cross-fade.
///
/// Below the header: the pipeline links into each member list, then the
/// web's cards in its order (sell-dashboard.container.html) — action items,
/// member breakdown, deal funnel. The web's greeting and PDF/CSV download
/// aren't mirrored.
struct ProjectDashboardView: View {
    let projectId: String
    let summary: ProjectSummary?
    let dashboard: ProjectDashboard?
    /// Distinguishes "not here yet" from "not coming" — skeleton vs. nothing.
    let isLoading: Bool
    /// A status change is in flight; the action items' status controls wait.
    var isPerforming = false
    /// An action item asked for a status change. The detail screen owns that
    /// flow (confirmation, counterparty sheet), same as its Manage menu.
    var onStatusAction: (ProjectAction) -> Void = { _ in }
    /// An action item wants a project setup step.
    var onOpenSetup: (SetupStep) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [SellsideDeal.Bucket] {
        dashboard?.populatedSections ?? []
    }

    /// Recomputed per render, which also stands in for the web's day clock:
    /// a dashboard reopened after the threshold passes picks the nudge up.
    private var actionItems: [ProjectActionItem] {
        dashboard.map { ProjectActionItem.items(for: $0) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProjectHeader(summary: summary, project: dashboard?.project)

            // The way into the member lists comes first — it's the screen's
            // navigation, and the cards below are context for it.
            section("Pipeline") { pipeline }

            if let dashboard, !actionItems.isEmpty {
                section("Action Items", count: actionItems.count) {
                    ActionItemsCard(
                        items: actionItems,
                        projectId: projectId,
                        supplyState: dashboard.project.supplyState,
                        isPerforming: isPerforming,
                        onStatusAction: onStatusAction,
                        onOpenSetup: onOpenSetup
                    )
                }
                .transition(.opacity)
            }

            section("Member Breakdown") {
                if let dashboard {
                    MemberBreakdownCard(dashboard: dashboard)
                        .transition(.opacity)
                } else if isLoading {
                    DashboardCardSkeleton(height: 220)
                        .transition(.opacity)
                }
            }

            section("Deal Funnel") {
                if let dashboard {
                    DealFunnelCard(
                        funnel: DealFunnel(dashboard: dashboard),
                        projectId: projectId,
                        hasInterestedMembers: !dashboard.interestedDeals.isEmpty
                    )
                    .transition(.opacity)
                } else if isLoading {
                    DashboardCardSkeleton(height: 420)
                        .transition(.opacity)
                }
            }
        }
        // Only the genuine swaps (skeleton → card, items arriving) animate;
        // the structure around them is fixed.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: dashboard == nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: actionItems.map(\.id))
    }

    /// A titled section. Hidden entirely once loading is over with nothing
    /// to show — a failed load has its own banner.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String, count: Int? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        if dashboard != nil || isLoading {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, count: count)
                content()
            }
        }
    }

    @ViewBuilder
    private var pipeline: some View {
        if let dashboard {
            ProjectSectionLinks(
                projectId: projectId,
                sections: sections,
                counts: Dictionary(uniqueKeysWithValues: sections.map { section in
                    (section, dashboard.deals(in: section).count)
                })
            )
            .transition(.opacity)
        } else if isLoading {
            ProjectSectionLinksSkeleton()
                .transition(.opacity)
        }
    }
}

private func previewDashboard(_ deals: [SellsideDeal]) -> ProjectDashboard {
    ProjectDashboard(
        project: ProjectDetail(id: "abc", internalName: "Project Neptune", supplyState: .inMarket),
        deals: deals
    )
}

#Preview("Loaded") {
    let dashboard = previewDashboard([
        .init(publicId: "d1", supplyStatus: .sentTeaser),
        .init(publicId: "d2", supplyStatus: .targetSignedNda, isInterested: true),
        .init(publicId: "d3", supplyStatus: .recommended),
        .init(publicId: "d4", supplyStatus: .recommended),
    ])
    return NavigationStack {
        ScrollView {
            ProjectDashboardView(
                projectId: "abc",
                summary: ProjectSummary(dashboard.project),
                dashboard: dashboard,
                isLoading: false
            )
            .padding(16)
        }
        .background(AxialColor.layer2)
    }
}

#Preview("Borrowed header, still loading") {
    NavigationStack {
        ScrollView {
            ProjectDashboardView(
                projectId: "abc",
                summary: ProjectSummary(ProjectDetail(
                    id: "abc",
                    internalName: "A Project With A Really Long Internal Name That Wraps",
                    supplyState: .readyToShare
                )),
                dashboard: nil,
                isLoading: true
            )
            .padding(16)
        }
        .background(AxialColor.layer2)
    }
}
