//
//  ActionItemsCard.swift
//  Sellside Mobile
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
            .cardSurface()
    }
}

/// A card-shaped placeholder for a section whose data hasn't landed: the
/// card itself, with placeholder lines in it. A bare grey block, as this
/// used to be, vanishes into the canvas, which is the same grey.
struct DashboardCardSkeleton: View {
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBox(width: 120, height: 14, cornerRadius: 6)
            SkeletonText(lines: 2, style: .subheadline, lastLineWidth: 180)
        }
        .shimmering()
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .cardSurface()
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
    /// Members with a request in flight.
    var busyDealIds: Set<String> = []
    let onStatusAction: (ProjectAction) -> Void
    /// A status change's confirmation opens from its action item.
    var statusConfirmation: Binding<Confirmation?> = .constant(nil)
    var onResolve: (ProjectActionItem.ResolveSheet) -> Void = { _ in }
    /// A bulk control fired, over these members.
    var onBulk: (ProjectActionItem.BulkAction, [SellsideDeal]) -> Void = { _, _ in }
    /// For a bulk control's members.
    var dashboard: ProjectDashboard?
    /// Where the CTAs register as zoom sources for the sheets they open.
    var transitionNamespace: Namespace.ID?

    /// "resolve.<sheet>" — matched by the detail screen's sheet.
    static func sourceID(_ sheet: ProjectActionItem.ResolveSheet) -> String { "resolve.\(sheet.rawValue)" }
    /// "bulk.<action>" — matched by the deal resolver's sheet.
    static func sourceID(_ action: ProjectActionItem.BulkAction) -> String { "bulk.\(action.rawValue)" }

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

        case .bulk(let segment, let action):
            let deals = dashboard.map(segment.deals) ?? []
            rowBody(item) {
                // Separate lenses with room between them. A shared
                // `GlassEffectContainer` merged the pair while one was
                // pressed, which read as the buttons bleeding together.
                HStack(spacing: 12) {
                    Button(action.label) {
                        Haptics.lightImpact()
                        onBulk(action, deals)
                    }
                    .buttonStyle(.glassProminent)
                    // Also waits on the members' own requests: a lone accept
                    // goes straight through, so a double tap would send it twice.
                    .disabled(isPerforming || deals.isEmpty || deals.contains { busyDealIds.contains($0.id) })
                    .accessibilityIdentifier("action-item-\(item.kind.rawValue)-bulk")
                    NavigationLink(deals.count == 1 ? "Review Member" : "Review Members",
                                   value: ProjectsRoute.segment(projectId: projectId, segment: segment))
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("action-item-\(item.kind.rawValue)-review")
                }
                .controlSize(.small)
            }
            // The row, not the button: the sheet lands on solid card.
            .zoomSource(id: Self.sourceID(action), in: transitionNamespace, cornerRadius: Self.cardRadius)

        case .status(let action, let ctaLabel):
            rowBody(item) {
                Button(ctaLabel) {
                    Haptics.lightImpact()
                    onStatusAction(action)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(isPerforming)
                .confirmation(statusConfirmation, anchor: ProjectStatusRequest.actionItem)
                .accessibilityIdentifier("action-item-\(item.kind.rawValue)-cta")
            }

        case .statusMenu:
            rowBody(item) {
                Menu("Update Status") {
                    ProjectStatusMenuItems(groups: ProjectAction.menu(for: supplyState), title: "Update Status",
                                           onSelect: onStatusAction)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isPerforming)
                .confirmation(statusConfirmation, anchor: ProjectStatusRequest.actionItem)
                .accessibilityIdentifier("action-item-\(item.kind.rawValue)-menu")
            }

        case .resolve(let sheet):
            rowBody(item) {
                Button(sheet.ctaLabel) {
                    Haptics.lightImpact()
                    onResolve(sheet)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .accessibilityIdentifier("action-item-\(item.kind.rawValue)-cta")
            }
            .zoomSource(id: Self.sourceID(sheet), in: transitionNamespace, cornerRadius: Self.cardRadius)
        }
    }

    /// A row lands its sheet in the card's own radius. That matches the
    /// card's corners on the first and last rows; on a row's inner edges the
    /// rounding falls on the same white fill, so it doesn't show. (The
    /// transition only clips to a uniform `RoundedRectangle`.)
    private static let cardRadius = AxialRadius.card

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
        .background(AxialColor.canvas)
    }
}
