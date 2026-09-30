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
    let projectDetailStore: ProjectDetailStore

    init() {
        let authService = AuthenticationService()
        self.authService = authService
        let apiClient = APIClient(authService: authService)
        self.apiClient = apiClient
        let projectsStore = ProjectsStore(apiClient: apiClient)
        self.projectsStore = projectsStore
        self.projectDetailStore = ProjectDetailStore(apiClient: apiClient, projectsStore: projectsStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiClient)
                .environment(projectsStore)
                .environment(projectDetailStore)
        }
    }
}
