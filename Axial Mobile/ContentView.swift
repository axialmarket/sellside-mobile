//
//  ContentView.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthenticationService()
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Auth0 Sample")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if authService.isLoading {
                LoadingView()
            } else if authService.isAuthenticated {
                AuthenticatedView(authService: authService)
            } else {
                UnauthenticatedView(authService: authService)
            }
            
            Spacer()
        }
        .padding()
        .alert("Error", isPresented: .constant(authService.errorMessage != nil)) {
            Button("OK") { authService.errorMessage = nil }
        } message: {
            Text(authService.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
}
