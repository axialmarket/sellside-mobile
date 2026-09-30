//
//  ProjectDashboardView.swift
//  Axial Mobile
//

import SwiftUI

/// A project's root screen: who it is, where it stands, and the way into its
/// member lists. Everything else about the project hangs off here.
///
/// Pure presentation — it takes a loaded `ProjectDashboard`, so it previews
/// and reads without any store wiring.
struct ProjectDashboardView: View {
    let dashboard: ProjectDashboard

    private var sections: [SellsideDeal.Bucket] {
        dashboard.populatedSections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProjectHeader(summary: ProjectSummary(dashboard.project))

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Pipeline")
                ProjectSectionLinks(
                    projectId: dashboard.project.id,
                    sections: sections,
                    counts: Dictionary(uniqueKeysWithValues: sections.map { section in
                        (section, dashboard.deals(in: section).count)
                    })
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            ProjectDashboardView(
                dashboard: ProjectDashboard(
                    project: ProjectDetail(
                        id: "abc", internalName: "Project Neptune", supplyState: .inMarket
                    ),
                    deals: [
                        .init(publicId: "d1", supplyStatus: .sentTeaser),
                        .init(publicId: "d2", supplyStatus: .targetSignedNda, isInterested: true),
                        .init(publicId: "d3", supplyStatus: .recommended),
                        .init(publicId: "d4", supplyStatus: .recommended),
                    ]
                )
            )
            .padding(16)
        }
        .background(AxialColor.layer2)
    }
}

#Preview("Nothing shared yet") {
    NavigationStack {
        ScrollView {
            ProjectDashboardView(
                dashboard: ProjectDashboard(
                    project: ProjectDetail(
                        id: "abc",
                        internalName: "A Project With A Really Long Internal Name That Wraps",
                        supplyState: .draft
                    )
                )
            )
            .padding(16)
        }
        .background(AxialColor.layer2)
    }
}
