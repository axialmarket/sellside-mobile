//
//  OffNetworkView.swift
//  Sellside Mobile
//

import SwiftUI

/// What a screen shows when the network gate turns it away — the
/// environment is VPN-only, and this phone isn't on the VPN
/// (`APIError.isOffNetwork`, CHALLENGES #8). Says what to do, rather than
/// "Server error: 503", and retries once they have. Only ever shown when the
/// build's API is marked VPN-only (`API_REQUIRES_VPN`).
struct OffNetworkView: View {
    let onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label("Connect to the VPN", systemImage: "lock.shield")
        } description: {
            Text(APIError.offNetworkMessage)
        } actions: {
            Button {
                Task {
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            } label: {
                // Both always there, so the button keeps its size.
                Text("Try Again")
                    .opacity(isRetrying ? 0 : 1)
                    .overlay { ProgressView().opacity(isRetrying ? 1 : 0) }
            }
            .buttonStyle(.glassProminent)
            .disabled(isRetrying)
            .accessibilityIdentifier("off-network-retry")
        }
        .accessibilityIdentifier("off-network")
    }
}

#Preview {
    OffNetworkView { try? await Task.sleep(for: .seconds(1)) }
}
