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
    let dealDetailStore: DealDetailStore
    let accountPresenter = AccountPresenter()

    init() {
        let authService: AuthenticationService
        let api: any APIRequesting
        #if DEBUG
        if UITestMode.isActive {
            // UI tests: signed in, fixture data, no network (CHALLENGES #12).
            authService = AuthenticationService(uiTesting: ())
            api = FixtureAPI()
        } else {
            authService = AuthenticationService()
            api = APIClient(authService: authService)
        }
        #else
        authService = AuthenticationService()
        api = APIClient(authService: authService)
        #endif
        self.authService = authService
        // Kept for the one view that still reads it from the environment
        // (the financials editor); every store goes through `api`.
        let apiClient = (api as? APIClient) ?? APIClient(authService: authService)
        self.apiClient = apiClient
        let projectsStore = ProjectsStore(apiClient: api)
        self.projectsStore = projectsStore
        self.projectDashboardStore = ProjectDashboardStore(apiClient: api, projectsStore: projectsStore)
        self.dealDetailStore = DealDetailStore(apiClient: api)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(apiClient)
                .environment(projectsStore)
                .environment(projectDashboardStore)
                .environment(dealDetailStore)
                .environment(accountPresenter)
        }
    }
}
