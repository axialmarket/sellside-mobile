//
//  DealList.swift
//  Sellside Mobile
//

import SwiftUI

/// A list's member cards, as `List` rows — rows rather than a stack so each
/// card can carry swipe actions. Lazy either way, which matters: a busy
/// project carries hundreds. Grouped by status under pinned headers, as the
/// projects list is (`DealStatusSection`).
///
/// Each card mirrors the web's row, whose quick buttons show on hover. Here
/// they're swipes: left for the quick actions and a More button that opens
/// every option, right for Pass on a member waiting for approval. A long
/// press shows everything as a context menu. The card itself carries no
/// action buttons or ellipsis, so swipes and the long press are the way in.
struct DealList: View {
    let sections: [DealStatusSection]
    /// Off in Recommended: no status on the cards and no status headers,
    /// since every member there is Deal Not Shared.
    var showsStatus = true
    let busyDealIds: Set<String>
    let emptyMessage: String
    var transitionNamespace: Namespace.ID?
    /// Where each card registers as the source its deal screen zooms from.
    var openNamespace: Namespace.ID?
    var onOpen: ((SellsideDeal) -> Void)?
    /// Set in select mode: who's selected. A tap then toggles instead of
    /// opening, and the swipes and context menu step aside.
    var selectedIds: Set<String>?
    var onToggle: ((SellsideDeal) -> Void)?
    /// A swipe's Update Status, which asks which status.
    var onPickStatus: ((SellsideDeal) -> Void)?
    /// A swipe's More, which lists every option.
    var onMore: ((SellsideDeal) -> Void)?
    /// A confirmation for one member opens from their card.
    var confirmation: Binding<Confirmation?> = .constant(nil)
    let onAction: (SellsideDeal, DealActionRequest) -> Void

    /// Every card here is interested, so the label would repeat the title.
    private var everyoneIsInterested: Bool {
        !sections.isEmpty && sections.allSatisfy { $0.deals.allSatisfy(\.isInterested) }
    }

    var body: some View {
        if sections.isEmpty {
            EmptyStateCard(message: emptyMessage)
                .dealListRow()
        } else {
            let showsInterest = !everyoneIsInterested
            ForEach(sections) { section in
                Section {
                    ForEach(section.deals) { deal in
                        card(for: deal, showsInterest: showsInterest)
                    }
                } header: {
                    // Fixed for a list's lifetime, so this never flips.
                    if showsStatus {
                        ListSectionHeader(title: section.title, count: section.deals.count)
                            .accessibilityIdentifier("deal-section-\(section.key)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(for deal: SellsideDeal, showsInterest: Bool) -> some View {
        let isBusy = busyDealIds.contains(deal.id)
        DealRow(deal: deal, isBusy: isBusy,
                transitionNamespace: transitionNamespace,
                onOpen: tap(for: deal),
                selection: selectedIds.map { $0.contains(deal.id) },
                showsInterest: showsInterest,
                showsStatus: showsStatus)
        .zoomSource(id: deal.id, in: openNamespace, cornerRadius: DealRow.cornerRadius)
        .contextMenu {
            if selectedIds == nil, !isBusy {
                DealRowMenuItems(deal: deal) { onAction(deal, $0) }
            }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: DealRow.cornerRadius))
        .confirmation(confirmation, anchor: Confirmation.card(deal.id))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if selectedIds == nil, !isBusy {
                trailingSwipeButtons(for: deal)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if selectedIds == nil, !isBusy {
                ForEach(DealRowAction.leadingSwipe(for: deal)) { swipeButton($0, for: deal) }
            }
        }
        .dealListRow()
    }

    /// The trailing quick actions, outermost first, then More.
    @ViewBuilder
    private func trailingSwipeButtons(for deal: SellsideDeal) -> some View {
        ForEach(DealRowAction.trailingSwipe(for: deal)) { swipeButton($0, for: deal) }
        // Always offered: the sheet holds more than the quick actions —
        // messaging, comments and the deal's pages.
        Button {
            Haptics.lightImpact()
            onMore?(deal)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .tint(AxialColor.textPlaceholder)
        .accessibilityLabel("More actions")
    }

    private func swipeButton(_ action: DealRowAction, for deal: SellsideDeal) -> some View {
        Button {
            Haptics.lightImpact()
            if action == .updateStatus {
                onPickStatus?(deal)
            } else if let request = action.request {
                onAction(deal, request)
            }
        } label: {
            Label(action.shortLabel, systemImage: action.systemImage)
        }
        .tint(Self.swipeTint(for: action))
        .accessibilityLabel(action.label(for: deal))
        .accessibilityIdentifier("deal-swipe-\(action)")
    }

    /// Brand for the step forward, grey for a pass, red for an end.
    private static func swipeTint(for action: DealRowAction) -> Color {
        switch action {
        case .pass: AxialColor.textSecondary
        case .endDiscussions: AxialColor.error
        default: AxialColor.brandPrimary
        }
    }
}

extension View {
    /// A member list row: the card is its own surface, so no separator or
    /// row background, and the 14pt gap the project cards use.
    func dealListRow() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

extension DealList {
    fileprivate func tap(for deal: SellsideDeal) -> (() -> Void)? {
        if selectedIds != nil, let onToggle { return { onToggle(deal) } }
        return onOpen.map { open in { open(deal) } }
    }
}

/// Placeholder rows while a list is still in flight.
struct DealListSkeleton: View {
    var rows = 3

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<rows, id: \.self) { _ in
                // The card's shape: monogram and two lines, then status.
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        SkeletonBox(width: 40, height: 40, cornerRadius: 10)
                        SkeletonText(lines: 2, style: .subheadline, lastLineWidth: 140)
                    }
                    SkeletonBox(width: 110, height: 12, cornerRadius: 6)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(cornerRadius: DealRow.cornerRadius)
            }
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading members")
    }
}

/// The one card an empty tab shows, so empties read alike everywhere.
struct EmptyStateCard: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AxialColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardSurface()
    }
}

/// Shared section heading: title plus an optional count.
struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
            if let count {
                Text("\(count)")
                    .foregroundStyle(AxialColor.textPlaceholder)
                    .contentTransition(.numericText())
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AxialColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
