//
//  SplashView.swift
//  Sellside Mobile
//

import SwiftUI

/// Shown while stored credentials are checked on cold launch.
/// Matches SignInView's canvas so an authenticated launch never flashes it.
struct SplashView: View {
    var body: some View {
        ZStack {
            AxialColor.brandPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                AxialMark()
                    .fill(.white)
                    .frame(width: 112, height: 112 / AxialMark.aspectRatio)
                    .accessibilityElement()
                    .accessibilityLabel("Axial")
                    .accessibilityAddTraits(.isImage)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

#Preview {
    SplashView()
}
