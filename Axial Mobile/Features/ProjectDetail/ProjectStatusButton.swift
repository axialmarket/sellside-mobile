//
//  ProjectStatusButton.swift
//  Axial Mobile
//

import SwiftUI

/// The project's status, and the detail behind it.
///
/// Tapping it opens what the web shows on hover — touch has no hover, so the
/// detail has to be asked for.
///
/// It lives in the header, not the navigation bar. A popover anchored to a bar
/// item is a dead end on iOS 26: the bar hides its source item while the
/// popover is up and restores it afterwards through the Liquid Glass morph, so
/// a coloured capsule spends ~400ms as a blurred smear with its background
/// dropped out. Nothing in the app drives that animation. Anchored to ordinary
/// content, the same popover zooms cleanly out of the pill and back into it.
struct ProjectStatusButton: View {
    let state: SupplyState
    /// Nil until the project has loaded; the panel shows progress until then
    /// rather than the tap doing nothing.
    let project: ProjectDetail?

    @State private var isShowingDetail = false

    var body: some View {
        Button {
            Haptics.lightImpact()
            isShowingDetail = true
        } label: {
            // No chevron: the pill is the affordance, as it is on the web and
            // in Slack's equivalent.
            StatusTag(state: state)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Status: \(state.label)")
        .accessibilityHint("Shows project status details")
        .accessibilityIdentifier("project-status-button")
        .popover(isPresented: $isShowingDetail) {
            ProjectStatusPopover(project: project)
        }
    }
}

/// The expanded detail — the mobile form of the web's hover card.
struct ProjectStatusPopover: View {
    let project: ProjectDetail?

    var body: some View {
        Group {
            if let project {
                rows(for: ProjectStatusDetail(project: project))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Loading status details")
            }
        }
        .padding(18)
        .frame(width: 270, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Clearing the system background does two things worth keeping: the
        // glass panel becomes the only surface, and the popover loses its
        // arrow — which is what lets it read as the pill zooming open and
        // collapsing back into itself rather than a callout pointing at it.
        .presentationBackground(.clear)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("project-status-detail")
    }

    private func rows(for detail: ProjectStatusDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(detail.rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.systemImage)
                        .font(.body)
                        .foregroundStyle(row.palette.foreground)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AxialColor.textPrimary)
                        if let subtitle = row.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(AxialColor.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview("In market, SmartShare") {
    ProjectStatusPopover(project: ProjectDetail(
        id: "a", internalName: "Neptune", supplyState: .inMarket,
        autoshareState: .enabled,
        autoshareExpiresAt: Calendar.current.date(byAdding: .day, value: 12, to: .now),
        inMarketDate: Calendar.current.date(byAdding: .day, value: -43, to: .now)
    ))
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AxialColor.layer2)
}

#Preview("Still loading") {
    ProjectStatusPopover(project: nil)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AxialColor.layer2)
}
