//
//  CardSurface.swift
//  Axial Mobile
//

import SwiftUI

/// The lift every card shares. A zoom transition out of a card repeats these
/// values in its source configuration, so the card doesn't change weight as
/// the push begins (see `ProjectsListView`).
enum CardShadow {
    static let opacity: Double = 0.07
    static let radius: CGFloat = 6
    static let y: CGFloat = 2
    static var color: Color { .black.opacity(opacity) }
}

extension View {
    /// A card on the canvas: `AxialColor.surface`, a hairline border and a
    /// soft shadow. The one definition, so cards read alike on every screen.
    ///
    /// `border` is for a card that marks a state with its outline, such as
    /// an unread message.
    func cardSurface(cornerRadius: CGFloat, border: Color = AxialColor.border) -> some View {
        background(AxialColor.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(border))
            .shadow(color: CardShadow.color, radius: CardShadow.radius, y: CardShadow.y)
    }
}
