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
    let projectDashboardStore: ProjectDashboardStore
    let accountPresenter = AccountPresenter()

    init() {
        let authService = AuthenticationService()
        self.authService = authService
        let apiClient = APIClient(authService: authService)
        self.apiClient = apiClient
        let projectsStore = ProjectsStore(apiClient: apiClient)
        self.projectsStore = projectsStore
        self.projectDashboardStore = ProjectDashboardStore(apiClient: apiClient, projectsStore: projectsStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiClient)
                .environment(projectsStore)
                .environment(projectDashboardStore)
                .environment(accountPresenter)
        }
    }
}
