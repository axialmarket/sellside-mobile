//
//  ContentView.swift
//  Axial Mobile
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationService.self) var authService

    private enum Phase {
        case checking, signedOut, signedIn
    }

    private var phase: Phase {
        if authService.isCheckingSession {
            .checking
        } else if authService.isAuthenticated {
            .signedIn
        } else {
            .signedOut
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .checking:
                SplashView()
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .signedIn:
                ProjectsListView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationService())
}
