//
//  ProjectDashboardView.swift
//  Axial Mobile
//

import SwiftUI

/// A project's root screen: who it is, where it stands, and the way into its
/// member lists.
///
/// Takes the project as an *optional* rather than being swapped in once it
/// loads. The header renders from the borrowed list row immediately, so the
/// screen is already correct before the fetch returns — and branching on the
/// load state out in the parent would rebuild this whole tree when it
/// resolves, which reads as a blink. Only the pipeline cards actually change,
/// so only they cross-fade.
struct ProjectDashboardView: View {
    let projectId: String
    let summary: ProjectSummary?
    let dashboard: ProjectDashboard?
    /// Distinguishes "not here yet" from "not coming" — skeleton vs. nothing.
    let isLoading: Bool

    private var sections: [SellsideDeal.Bucket] {
        dashboard?.populatedSections ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProjectHeader(summary: summary, project: dashboard?.project)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Pipeline")
                pipeline
            }
            .animation(.easeInOut(duration: 0.25), value: dashboard == nil)
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
