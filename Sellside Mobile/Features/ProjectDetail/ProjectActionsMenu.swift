//
//  ProjectActionsMenu.swift
//  Sellside Mobile
//

import SwiftUI

/// The web's "Manage Project" dropdown, as a toolbar menu.
///
/// Same shape as the web's: a "Manage Project" header with the status
/// changes nested one level down. The web's Edit Project and Sharing
/// Settings are left out on purpose — mobile resolves what moves a project
/// forward and leaves editing and configuration to the web (CHALLENGES #18).
/// The separators inside the status submenu are sections.
/// Same identity in every state — see `ProjectStatusButton` for why. A menu
/// that only exists once the project has loaded gets inserted rather than
/// morphed, and swapping it for a spinner while an action runs does the same,
/// so both are expressed as changes *inside* one `Menu`.
struct ProjectActionsMenu: View {
    /// Nil until the project has loaded.
    let menu: ManageProjectMenu?
    let isPerforming: Bool
    let onSelect: (ProjectAction) -> Void

    var body: some View {
        Menu {
            if let menu {
                content(menu)
            }
        } label: {
            if isPerforming {
                ProgressView()
            } else {
                Image(systemName: "ellipsis")
            }
        }
        // Nothing to offer for a status the app doesn't recognise.
        .disabled(menu?.statusGroups.isEmpty != false || isPerforming)
        .accessibilityLabel("Manage Project")
        .accessibilityIdentifier("manage-project-menu")
    }

    @ViewBuilder
    private func content(_ menu: ManageProjectMenu) -> some View {
        Group {
            Section("Manage Project") {
                updateStatusMenu(menu)
            }

        }
    }

    private func updateStatusMenu(_ menu: ManageProjectMenu) -> some View {
        Menu {
            ProjectStatusMenuItems(groups: menu.statusGroups, onSelect: onSelect)
        } label: {
            Label("Update Status", systemImage: "arrow.triangle.2.circlepath")
        }
    }
}
