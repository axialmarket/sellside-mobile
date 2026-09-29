//
//  SplashView.swift
//  Axial Mobile
//

import SwiftUI

/// Shown while stored credentials are checked on cold launch.
/// Matches SignInView's canvas so an authenticated launch never flashes it.
struct SplashView: View {
    var body: some View {
        ZStack {
            AxialColor.brandPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("axial")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

#Preview {
    SplashView()
}
