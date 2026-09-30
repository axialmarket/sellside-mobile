//
//  DealActionsMenu.swift
//  Axial Mobile
//

import SwiftUI

/// The per-deal row menu from the web's contacted-members grid.
///
/// Status changes nest one level down, as they do on the web — there are eight
/// of them and they'd bury everything else. The web's separators inside that
/// submenu become `Section`s.
struct DealActionsMenu: View {
    let deal: SellsideDeal
    let isBusy: Bool
    let onSelect: (DealActionRequest) -> Void

    private var actions: [DealAction] {
        DealAction.offered(for: deal)
    }

    var body: some View {
        Menu {
            ForEach(actions) { action in
                switch action {
                case .updateStatus:
                    updateStatusMenu
                case .endDiscussions:
                    Button(role: .destructive) {
                        onSelect(.endDiscussions)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
                    .accessibilityIdentifier("deal-action-endDiscussions")
                default:
                    EmptyView() // not offered on mobile yet — see DealAction.isImplemented
                }
            }
        } label: {
            label
        }
        .disabled(isBusy || actions.isEmpty)
        .accessibilityIdentifier("deal-actions-menu")
        .accessibilityLabel("Actions for \(deal.displayName)")
    }

    private var updateStatusMenu: some View {
        Menu {
            ForEach(DealStatusUpdateOption.groups.indices, id: \.self) { index in
                Section {
                    ForEach(DealStatusUpdateOption.groups[index]) { option in
                        Button(option.label) { onSelect(.updateStatus(option)) }
                            .accessibilityIdentifier("deal-status-\(option.rawValue)")
                    }
                }
            }
        } label: {
            Label(DealAction.updateStatus.label, systemImage: DealAction.updateStatus.systemImage)
        }
    }

    @ViewBuilder
    private var label: some View {
        if isBusy {
            ProgressView()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(AxialColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
    }
}
