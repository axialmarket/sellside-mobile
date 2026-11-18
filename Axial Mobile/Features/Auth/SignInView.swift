//
//  SignInView.swift
//  Axial Mobile
//

import SwiftUI

/// The brand moment: full-bleed Axial blue, the white mark, one button.
struct SignInView: View {
    @Environment(AuthenticationService.self) var authService

    var body: some View {
        ZStack {
            AxialColor.brandPrimary.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                AxialMark()
                    .fill(.white)
                    .frame(width: 112, height: 112 / AxialMark.aspectRatio)
                    // The name below says it.
                    .accessibilityHidden(true)

                Text("Axial for Sellers")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                if let message = authService.errorMessage {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AxialColor.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button {
                    Haptics.lightImpact()
                    Task { await authService.login() }
                } label: {
                    Group {
                        if authService.isLoading {
                            ProgressView().tint(AxialColor.brandPrimary)
                        } else {
                            Text("Sign In").font(.headline)
                        }
                    }
                    .foregroundStyle(AxialColor.brandPrimary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .controlSize(.large)
                .disabled(authService.isLoading)
            }
            .padding(24)
            .animation(.default, value: authService.errorMessage)
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthenticationService())
}
