//
//  ProjectHeader.swift
//  Sellside Mobile
//

import SwiftUI

/// Dashboard header: the project's name, then a row of its attributes.
///
/// The name gets the full width and the status sits on its own row beneath it.
/// The web puts them side by side because it has the width to spare; a phone
/// doesn't, and sharing a line costs either the name's width or a custom text
/// layout to flow around the pill. A second row is cheaper than both, and it's
/// where the rest of a project's attributes — sectors, assigned contact,
/// created date — will go.
///
/// The summary is whatever we know first — the tapped list row, then the
/// fetched project once it lands. Skeletons are for a genuinely cold open
/// (a deep link), where there's no row to borrow from.
///
/// Mirrors fe-app's `axl-sell-header`, which clamps the name to one line and
/// reveals the rest in a hover tooltip. Touch has no hover, so the name wraps
/// instead. `internal_name` is capped at 70 characters server-side
/// (`INTERNAL_NAME_MAX_CHARS`), but the cap isn't relied on, hence the line
/// limit — lifted at accessibility type sizes, where truncating the one thing
/// on screen would cost more than the scrolling it saves.
struct ProjectHeader: View {
    let summary: ProjectSummary?
    /// Drives the expandable status detail; nil until the project has loaded.
    var project: ProjectDetail?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary {
                Text(summary.internalName)
                    .font(.title.weight(.bold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                attributes(summary)
            } else {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One chip today. When it holds several, this is the row to make
    /// horizontally scrollable rather than let it wrap.
    private func attributes(_ summary: ProjectSummary) -> some View {
        HStack(spacing: 8) {
            ProjectStatusButton(state: summary.supplyState, project: project)
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonText(lines: 2, style: .title1, lastLineWidth: 160)
            SkeletonBox(width: 96, height: 24, cornerRadius: 12)
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading project")
    }
}

private func previewHeader(_ name: String, _ state: SupplyState) -> some View {
    ProjectHeader(
        summary: ProjectSummary(ProjectDetail(id: "p", internalName: name, supplyState: state)),
        project: ProjectDetail(id: "p", internalName: name, supplyState: state)
    )
}

#Preview("States") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            previewHeader("Project Neptune", .inMarket)
            previewHeader("Buyer Calculator Template - armannikoi20@gmail.com", .readyToShare)
            previewHeader(
                "Package of Gas Station Retail Locations for Sale, seeking a buyer",
                .reviewingLois
            )
            ProjectHeader(summary: nil)
        }
        .padding(16)
    }
    .background(AxialColor.canvas)
}
