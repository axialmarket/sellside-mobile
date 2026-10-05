//
//  ContentView.swift
//  Axial Mobile
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthenticationService.self) var authService
    @Environment(AccountPresenter.self) var accountPresenter
    @Namespace private var accountTransition

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
        @Bindable var accountPresenter = accountPresenter
        ZStack {
            switch phase {
            case .checking:
                SplashView()
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .signedIn:
                ProjectsListView(accountTransition: accountTransition)
                    // Attached here, above every navigation stack, so the
                    // sheet can open over whatever screen is showing.
                    .sheet(isPresented: $accountPresenter.isPresented) {
                        AccountSheet()
                            .navigationTransition(
                                .zoom(sourceID: AccountPresenter.transitionID, in: accountTransition))
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .onChange(of: phase) { _, newPhase in
            // A session that expires with the sheet up would otherwise
            // leave it marked open, and it'd reappear after signing back in.
            if newPhase != .signedIn { accountPresenter.dismiss() }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthenticationService())
        .environment(AccountPresenter())
}
