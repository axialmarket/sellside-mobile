//
//  CardSurface.swift
//  Axial Mobile
//

import SwiftUI

extension View {
    /// A card on the canvas: `AxialColor.surface` with a hairline border.
    /// The one definition, so cards read alike on every screen.
    ///
    /// Flat, with no shadow. The canvas and the border are what set a card
    /// apart, and every card in the app — projects, the dashboard, members,
    /// the deal screen — uses this, so none of them carries a lift the
    /// others don't.
    ///
    /// `border` is for a card that marks a state with its outline, such as
    /// an unread message.
    func cardSurface(cornerRadius: CGFloat = AxialRadius.card, border: Color = AxialColor.border) -> some View {
        background(AxialColor.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(border))
    }
}
