//
//  CardButtonStyle.swift
//  Sellside Mobile
//

import SwiftUI

/// Makes a whole card tappable without a `NavigationLink`'s disclosure
/// chevron: no tint, just a press-in that reads as "this row is a button".
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
