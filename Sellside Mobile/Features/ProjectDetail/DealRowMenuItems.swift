//
//  DealRowMenuItems.swift
//  Sellside Mobile
//

import SwiftUI

/// One row's actions as menu items, for the card's context menu.
///
/// Status changes nest one level down, as they do on the web — there are
/// eight of them and they'd bury everything else.
struct DealRowMenuItems: View {
    let deal: SellsideDeal
    let onSelect: (DealActionRequest) -> Void

    var body: some View {
        ForEach(DealRowAction.menu(for: deal)) { action in
            if action == .updateStatus {
                Menu {
                    DealStatusMenuItems { onSelect(.updateStatus($0)) }
                } label: {
                    Label(action.label(for: deal), systemImage: action.systemImage)
                }
            } else if let request = action.request {
                Button(role: action.isDestructive ? .destructive : nil) {
                    onSelect(request)
                } label: {
                    Label(action.label(for: deal), systemImage: action.systemImage)
                }
                .accessibilityIdentifier("deal-action-\(action)")
            }
        }
        .tint(AxialColor.textPrimary)
    }
}
