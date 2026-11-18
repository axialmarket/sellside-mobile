//
//  AxialRadius.swift
//  Axial Mobile
//

import SwiftUI

/// The app's corner radii, so screens stop choosing their own. Three steps,
/// each a level of nesting:
///
/// - `card` — a card on the canvas (`cardSurface`), and the zoom
///   transitions that grow out of one.
/// - `well` — a box inside a card: an inset well (`insetWell`), a callout,
///   a text field.
/// - `control` — something small inside that: an icon tile, a chip, a form
///   row.
///
/// Capsules and glass buttons keep their own shapes.
enum AxialRadius {
    static let card: CGFloat = 16
    static let well: CGFloat = 12
    static let control: CGFloat = 8
}

extension View {
    /// A well inside a card: `AxialColor.inset` with a hairline border, as
    /// the project card's counts strip and the deal card's message line use.
    /// The one definition, so every recessed box inside a card reads alike.
    func insetWell(cornerRadius: CGFloat = AxialRadius.well) -> some View {
        background(AxialColor.inset, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(AxialColor.border))
    }
}
