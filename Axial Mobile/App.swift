//
//  App.swift
//  Axial Mobile
//

import SwiftUI

@main
struct AxialMobileApp: App {
    let authService: AuthenticationService
    let apiClient: APIClient
    let projectsStore: ProjectsStore

    init() {
        let authService = AuthenticationService()
        self.authService = authService
        let apiClient = APIClient(authService: authService)
        self.apiClient = apiClient
        self.projectsStore = ProjectsStore(apiClient: apiClient)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiClient)
                .environment(projectsStore)
        }
    }
}
