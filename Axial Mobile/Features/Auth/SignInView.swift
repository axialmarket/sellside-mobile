//
//  SignInView.swift
//  Axial Mobile
//

import SwiftUI

/// The brand moment: full-bleed Axial blue, white wordmark, one button.
struct SignInView: View {
    @Environment(AuthenticationService.self) var authService

    var body: some View {
        ZStack {
            AxialColor.brandPrimary.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("axial")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Where deals get done")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))

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
