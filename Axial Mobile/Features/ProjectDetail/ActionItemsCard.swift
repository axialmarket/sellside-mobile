//
//  ActionItemsCard.swift
//  Axial Mobile
//

import SwiftUI

/// The surface every dashboard card sits on — the pipeline cards' styling.
struct DashboardCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AxialColor.border))
    }
}

/// A card-shaped placeholder for a section whose data hasn't landed.
struct DashboardCardSkeleton: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(AxialColor.layer3)
            .frame(height: height)
            .shimmering()
            .accessibilityHidden(true)
    }
}

/// The dashboard's to-do list. Mirrors fe-app's `axl-action-items` and the
/// per-item components under sell-dashboard/action-items — each row's
/// trailing control is decided by `ProjectActionItem.control`, not here.
struct ActionItemsCard: View {
    let items: [ProjectActionItem]
    let projectId: String
    /// For the stale nudge's status menu.
    let supplyState: SupplyState
    let isPerforming: Bool
    let onStatusAction: (ProjectAction) -> Void
    var onOpenSetup: (SetupStep) -> Void = { _ in }

    var body: some View {
        DashboardCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    /// One branch per control. Each item keeps its control for as long as it
    /// exists — a change of control is a change of `id` — so these branches
    /// never swap under a live row.
    @ViewBuilder
    private func row(_ item: ProjectActionItem) -> some View {
        switch item.control {
        case .segment(let segment):
            NavigationLink(value: ProjectsRoute.segment(projectId: projectId, segment: segment)) {
                rowBody(item, showsChevron: true) { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("action-item-\(item.kind.rawValue)")

        case .status(let action, let ctaLabel):
            rowBody(item) {
                Button(ctaLabel) {
                    Haptics.lightImpact()
                    onStatusAction(action)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPerforming)
                .accessibilityIdentifier("action-item-\(item.kind.rawValue)-cta")
            }

        case .statusMenu:
            rowBody(item) {
                Menu("Update Status") {
                    ForEach(Array(ProjectAction.menu(for: supplyState).enumerated()), id: \.offset) { _, group in
                        Section {
                            ForEach(group) { action in
                                Button(role: action.isDestructive ? .destructive : nil) {
                                    onStatusAction(action)
                                } label: {
                                    Label(action.label, systemImage: action.systemImage)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPerforming)
                .accessibilityIdentifier("action-item-\(item.kind.rawValue)-menu")
            }

        case .setup(let step):
            Button {
                Haptics.lightImpact()
                onOpenSetup(step)
            } label: {
                rowBody(item, showsChevron: true) { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("action-item-\(item.kind.rawValue)")
        }
    }

    private func rowBody<Control: View>(
        _ item: ProjectActionItem,
        showsChevron: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body)
                .foregroundStyle(AxialColor.brandPrimary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                Text(item.description)
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                control()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AxialColor.textPlaceholder)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .contentShape(.rect)
    }
}

#Preview {
    let dashboard = ProjectDashboard(
        project: ProjectDetail(id: "abc", internalName: "Neptune", supplyState: .inMarket, hasCim: true),
        deals: [
            .init(publicId: "d1", supplyStatus: .targetRequestedAccess, isInterested: true),
            .init(publicId: "d2", supplyStatus: .markedClosed, isInterested: true),
            .init(publicId: "d3", supplyStatus: .targetSignedNda, isInterested: true,
                  hasTargetPursued: true, hasSignedNda: true),
        ]
    )
    NavigationStack {
        ScrollView {
            ActionItemsCard(
                items: ProjectActionItem.items(for: dashboard),
                projectId: "abc", supplyState: .inMarket, isPerforming: false,
                onStatusAction: { _ in }
            )
            .padding(16)
        }
        .background(AxialColor.layer2)
    }
}
