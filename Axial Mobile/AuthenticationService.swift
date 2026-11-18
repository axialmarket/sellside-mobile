//
//  AuthenticationService.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import Foundation
import Auth0
import Combine

@MainActor
@Observable
class AuthenticationService {
    var isAuthenticated = false
    var user: UserInfo?
    var isLoading = false
    var isCheckingSession = true
    var errorMessage: String?
    
    private let credentialsManager: CredentialsManager
    
    init() {
        let auth = Auth0.authentication(
            clientId: Auth0Config.shared.clientId,
            domain: Auth0Config.shared.domain
        )
        
        credentialsManager = CredentialsManager(authentication: auth)
        
        Task {
            await checkAuthenticationStatus()
        }
    }
    
    #if DEBUG
    /// UI tests (`UITestMode`): signed in from the first frame, with no
    /// stored credentials and no Auth0 round trip. The API is a fixture, so
    /// there's no token to send.
    init(uiTesting: Void) {
        credentialsManager = CredentialsManager(authentication: Auth0.authentication(
            clientId: Auth0Config.shared.clientId,
            domain: Auth0Config.shared.domain
        ))
        isAuthenticated = true
        isCheckingSession = false
    }
    #endif

    var accessToken: String? {
        get async {
            do {
                let credentials = try await credentialsManager.credentials()
                return credentials.accessToken
            } catch {
                return nil
            }
        }
    }
    
    private func checkAuthenticationStatus() async {
        defer { isCheckingSession = false }

        guard let _ = try? await credentialsManager.credentials() else {
            isAuthenticated = false
            return
        }
        
        isAuthenticated = true
        // Get user info from the ID token
        user = credentialsManager.user
    }
    
    func login() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let credentials = try await Auth0
                .webAuth(
                    clientId: Auth0Config.shared.clientId,
                    domain: Auth0Config.shared.domain
                )
                .audience("https://axialmarket.com")
                .scope("openid profile email offline_access")
                .start()
            
            _ = credentialsManager.store(credentials: credentials)
            isAuthenticated = true
            // Get user info from the ID token
            user = credentialsManager.user
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }
    }
    
    func logout() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await Auth0
                .webAuth(
                    clientId: Auth0Config.shared.clientId,
                    domain: Auth0Config.shared.domain
                )
                .clearSession(federated: true)
            
            _ = credentialsManager.clear()
            isAuthenticated = false
            user = nil
            
        } catch {
            errorMessage = "Logout failed: \(error.localizedDescription)"
        }
    }

    /// Clears local credentials after the API rejects our token (401).
    func expireSession() {
        _ = credentialsManager.clear()
        isAuthenticated = false
        user = nil
        errorMessage = "Your session expired. Please sign in again."
    }
}
