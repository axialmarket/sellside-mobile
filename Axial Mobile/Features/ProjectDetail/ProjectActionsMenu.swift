//
//  ProjectActionsMenu.swift
//  Axial Mobile
//

import SwiftUI

/// What the Manage Project menu can raise.
enum ProjectMenuAction: Hashable {
    case status(ProjectAction)
    case sharingSettings
    case editProject
}

/// The web's "Manage Project" dropdown, as a toolbar menu.
///
/// Same shape as the web's: a "Manage Project" header, the status changes
/// nested one level down, Sharing Settings beside them, and Edit Project below
/// a divider. The divider is a second `Section`, and the separators inside the
/// status submenu are sections too.
/// Same identity in every state — see `ProjectStatusButton` for why. A menu
/// that only exists once the project has loaded gets inserted rather than
/// morphed, and swapping it for a spinner while an action runs does the same,
/// so both are expressed as changes *inside* one `Menu`.
struct ProjectActionsMenu: View {
    /// Nil until the project has loaded.
    let menu: ManageProjectMenu?
    let isPerforming: Bool
    let onSelect: (ProjectMenuAction) -> Void

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
        .disabled(menu == nil || isPerforming)
        .accessibilityLabel("Manage Project")
        .accessibilityIdentifier("manage-project-menu")
    }

    @ViewBuilder
    private func content(_ menu: ManageProjectMenu) -> some View {
        Group {
            Section("Manage Project") {
                if !menu.statusGroups.isEmpty {
                    updateStatusMenu(menu)
                }
                if menu.showsSharingSettings {
                    Button {
                        onSelect(.sharingSettings)
                    } label: {
                        Label("Sharing Settings", systemImage: "square.and.arrow.up")
                    }
                    .disabled(menu.sharingSettingsIsDisabled)
                    .accessibilityIdentifier("project-action-sharingSettings")
                }
            }

            Section {
                Button {
                    onSelect(.editProject)
                } label: {
                    Label("Edit Project", systemImage: "pencil")
                }
                .accessibilityIdentifier("project-action-editProject")
            }
        }
    }

    private func updateStatusMenu(_ menu: ManageProjectMenu) -> some View {
        Menu {
            ForEach(menu.statusGroups.indices, id: \.self) { index in
                Section {
                    ForEach(menu.statusGroups[index]) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            onSelect(.status(action))
                        } label: {
                            Label(action.label, systemImage: action.systemImage)
                        }
                        .accessibilityIdentifier("project-action-\(action.rawValue)")
                    }
                }
            }
        } label: {
            Label("Update Project Status", systemImage: "arrow.triangle.2.circlepath")
        }
    }
}
