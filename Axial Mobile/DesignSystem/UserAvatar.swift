//
//  UserAvatar.swift
//  Axial Mobile
//

import SwiftUI

/// The signed-in user's initials in a brand-coloured circle — the toolbar's
/// account button and the Account sheet's header card.
struct UserAvatar: View {
    let name: String?
    var size: CGFloat = 30

    var body: some View {
        Text(AccountInitials.from(name: name))
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(AxialColor.brandPrimary, in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        UserAvatar(name: "Jordan Reyes")
        UserAvatar(name: nil, size: 56)
    }
}
