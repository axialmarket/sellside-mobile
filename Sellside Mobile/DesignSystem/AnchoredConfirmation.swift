//
//  AnchoredConfirmation.swift
//  Sellside Mobile
//

import SwiftUI

/// A confirmation that opens from the control or card that asked for it.
///
/// A `confirmationDialog` presents from the view it's attached to; on iOS 26
/// that's a popover pointing at that view. Attached to a whole screen, it
/// pointed at the top of the screen whatever was tapped — a swiped card's
/// Pass, a footer's End Discussions. Here the request names its anchor, and
/// each view that can be one carries `.confirmation(_:anchor:)`; only the
/// one whose anchor matches presents.
struct Confirmation: Identifiable {
    /// Which view it opens from, e.g. `Confirmation.card(deal.id)`.
    let anchor: String
    let title: String
    let message: String
    let confirm: String
    var isDestructive = true
    let perform: () -> Void

    var id: String { "\(anchor)|\(title)" }

    static func card(_ id: String) -> String { "card-\(id)" }
}

extension View {
    /// Presents `confirmation` from this view when its anchor is `anchor`.
    func confirmation(_ confirmation: Binding<Confirmation?>, anchor: String) -> some View {
        let isPresented = Binding(
            get: { confirmation.wrappedValue?.anchor == anchor },
            set: { if !$0 { confirmation.wrappedValue = nil } }
        )
        return confirmationDialog(
            confirmation.wrappedValue?.title ?? "",
            isPresented: isPresented,
            titleVisibility: .visible,
            presenting: confirmation.wrappedValue
        ) { pending in
            Button(pending.confirm, role: pending.isDestructive ? .destructive : nil) {
                pending.perform()
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }
}
