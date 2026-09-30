//
//  ProjectHeader.swift
//  Axial Mobile
//

import SwiftUI

/// Dashboard header: the project's name and status, or their skeletons.
///
/// The summary is whatever we know first — the tapped list row, then the
/// fetched project once it lands. Skeletons are for a genuinely cold open
/// (a deep link), where there's no row to borrow from.
///
/// Mirrors fe-app's `axl-sell-header`, which clamps the name to one line and
/// reveals the rest in a hover tooltip. Touch has no hover, so the name wraps
/// instead. `internal_name` is capped at 70 characters server-side
/// (`INTERNAL_NAME_MAX_CHARS`) — roughly four wrapped lines at `.title` on a
/// phone — but the cap isn't relied on, hence the line limit. It's lifted at
/// accessibility type sizes, where truncating the one thing on screen would
/// cost more than the scrolling it saves.
struct ProjectHeader: View {
    let summary: ProjectSummary?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                Text(summary.internalName)
                    .font(.title.weight(.bold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                StatusTag(state: summary.supplyState)
            } else {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonText(lines: 2, style: .title1, lastLineWidth: 190)
            SkeletonBox(width: 110, height: 26, cornerRadius: 13)
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading project")
    }
}

#Preview("States") {
    VStack(spacing: 32) {
        ProjectHeader(summary: ProjectSummary(ProjectDetail(
            id: "1350c847f3fd7fadcbd5734197b634bd",
            internalName: "Project Neptune",
            supplyState: .inMarket
        )))
        ProjectHeader(summary: ProjectSummary(ProjectDetail(
            id: "2350c847f3fd7fadcbd5734197b634bd",
            internalName: "Package of Gas Station Retail Locations for Sale, seeking a buyer",
            supplyState: .reviewingLois
        )))
        ProjectHeader(summary: nil)
    }
    .padding(16)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(AxialColor.layer2)
}
