//
//  DealActionsSheet.swift
//  Axial Mobile
//

import SwiftUI

/// Everything one member's row can do, as a sheet — what a swipe's More
/// opens, laid out like Mail's: the member and a line of context with a
/// close button, up to four tiles across (moving forward first, the
/// destructive one last and red), then grouped rows with their icons
/// trailing. `DealActionsLayout` decides what goes where.
///
/// Update Status pushes to its options inside the sheet, so there's no
/// second sheet to chain. Picking anything else hands it back and closes the
/// sheet; the caller runs it once the sheet is gone (`onDismiss`), so a
/// confirmation or another sheet never presents over this one on its way out.
struct DealActionsSheet: View {
    let deal: SellsideDeal
    let onSelect: (DealActionRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page]

    enum Page: Hashable { case status }

    /// `startsOnStatus` opens straight on the status options — a swiped
    /// Update Status — with the full sheet a back swipe away.
    init(deal: SellsideDeal, startsOnStatus: Bool = false, onSelect: @escaping (DealActionRequest) -> Void) {
        self.deal = deal
        self.onSelect = onSelect
        _path = State(initialValue: startsOnStatus ? [.status] : [])
    }

    private var layout: DealActionsLayout { DealActionsLayout(deal: deal) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    tiles
                } header: {
                    header
                        .textCase(nil)
                        .padding(.bottom, 12)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                ForEach(layout.sections.indices, id: \.self) { index in
                    Section {
                        ForEach(layout.sections[index]) { item in
                            row(item)
                        }
                    }
                }
            }
            .listSectionSpacing(14)
            .contentMargins(.top, 8, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { _ in
                DealStatusPage(deal: deal) { choose(.updateStatus($0)) }
            }
        }
        .tint(AxialColor.textPrimary)
        .accessibilityIdentifier("deal-actions-sheet")
    }

    // MARK: Header

    /// Who it's about and one line of context — the last message, else the
    /// status — with the close button beside it, as Mail's sheet has.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            CompanyMonogram(name: deal.displayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(deal.displayName)
                    .font(.headline)
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(1)
                Text(deal.lastMessagePreview ?? deal.displayStatus.label)
                    .font(.subheadline)
                    .foregroundStyle(AxialColor.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("deal-actions-close")
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 12) {
            ForEach(layout.tiles) { item in
                Button {
                    Haptics.lightImpact()
                    select(item)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: icon(for: item))
                            .font(.title3.weight(.semibold))
                            .frame(height: 24)
                        Text(shortTitle(for: item))
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(isDestructive(item) ? AxialColor.errorText : AxialColor.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .accessibilityLabel(title(for: item))
                .accessibilityIdentifier("deal-sheet-tile-\(item)")
            }
        }
    }

    // MARK: Rows

    /// Title leading, icon trailing — Mail's rows.
    @ViewBuilder
    private func row(_ item: DealActionsLayout.Item) -> some View {
        let label = HStack {
            Text(title(for: item))
            Spacer(minLength: 8)
            Image(systemName: icon(for: item))
                .frame(width: 24)
        }
        .foregroundStyle(isDestructive(item) ? AxialColor.errorText : AxialColor.textPrimary)

        if item == .action(.updateStatus) {
            NavigationLink(value: Page.status) { label }
                .accessibilityIdentifier("deal-sheet-updateStatus")
        } else {
            Button { select(item) } label: { label }
                .accessibilityIdentifier("deal-sheet-\(item)")
        }
    }

    // MARK: Item text

    private func title(for item: DealActionsLayout.Item) -> String {
        switch item {
        case .action(let action): action.label(for: deal)
        case .compose(.message): "Send Message"
        case .compose(.comment): "Add Internal Comment"
        case .view(let tab): "View \(tab.title)"
        }
    }

    /// A tile has room for a word or two.
    private func shortTitle(for item: DealActionsLayout.Item) -> String {
        switch item {
        case .action(let action): action.shortLabel
        case .compose(.message): "Message"
        case .compose(.comment): "Comment"
        case .view(let tab): tab.title
        }
    }

    private func icon(for item: DealActionsLayout.Item) -> String {
        switch item {
        case .action(let action): action.systemImage
        case .compose(.message): "arrowshape.turn.up.left"
        case .compose(.comment): "bubble.left"
        case .view(.profile): "person.text.rectangle"
        case .view(.messages): "bubble.left.and.bubble.right"
        case .view(.files): "doc.on.doc"
        case .view(.comments): "text.bubble"
        }
    }

    private func isDestructive(_ item: DealActionsLayout.Item) -> Bool {
        if case .action(let action) = item { return action.isDestructive }
        return false
    }

    // MARK: Choosing

    private func select(_ item: DealActionsLayout.Item) {
        switch item {
        case .action(.updateStatus): path.append(.status)
        case .action(let action): action.request.map(choose)
        case .compose(let compose): choose(.compose(compose))
        case .view(let tab): choose(.open(tab))
        }
    }

    private func choose(_ request: DealActionRequest) {
        onSelect(request)
        dismiss()
    }
}

/// The status options, grouped at the web's separators, with the member's
/// current status ticked.
private struct DealStatusPage: View {
    let deal: SellsideDeal
    let onSelect: (DealStatusUpdateOption) -> Void

    var body: some View {
        List {
            ForEach(DealStatusUpdateOption.groups.indices, id: \.self) { index in
                Section {
                    ForEach(DealStatusUpdateOption.groups[index]) { option in
                        Button {
                            Haptics.selection()
                            onSelect(option)
                        } label: {
                            HStack {
                                Label(option.label, systemImage: option.systemImage)
                                    .foregroundStyle(AxialColor.textPrimary)
                                Spacer()
                                if option.isCurrent(for: deal) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AxialColor.brandPrimary)
                                        .accessibilityLabel("Current status")
                                }
                            }
                        }
                        .accessibilityIdentifier("deal-status-\(option.rawValue)")
                    }
                }
            }
        }
        .navigationTitle("Update Status")
        .navigationBarTitleDisplayMode(.inline)
    }
}
