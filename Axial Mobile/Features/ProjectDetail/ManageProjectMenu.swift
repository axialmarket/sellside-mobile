//
//  ManageProjectMenu.swift
//  Axial Mobile
//

import Foundation

/// What the Manage Project menu offers for a given project.
///
/// Mirrors the status submenu of `manageMenuItems` in fe-app's
/// manage-project.component.ts. The web's Sharing Settings and Edit Project
/// items stay on the web (CHALLENGES #18).
struct ManageProjectMenu: Equatable {
    /// Status changes, grouped the way the web separates them.
    let statusGroups: [[ProjectAction]]

    init(project: ProjectDetail) {
        statusGroups = ProjectAction.menu(for: project.supplyState)
    }
}

extension ProjectDetail {
    /// Web disables Copy Deal Link until the project is complete — there's
    /// nothing worth linking to before then.
    var canCopyDealLink: Bool {
        isComplete
    }
}
