//
//  ProjectActionsMenu.swift
//  Axial Mobile
//

import SwiftUI

/// The web's "Manage Project" dropdown as a toolbar Menu.
///
/// Web nests the status changes one level down, under "Update Project Status",
/// alongside Sharing Settings and Edit Project. Neither of those exists on
/// mobile yet, so a submenu holding a single group would be a tap for nothing —
/// the statuses sit at the top level until there's something to sit beside.
/// The web's separators become `Section`s.
struct ProjectActionsMenu: View {
    let supplyState: SupplyState
    let isEnabled: Bool
    let onSelect: (ProjectAction) -> Void

    private var groups: [[ProjectAction]] {
        ProjectAction.menu(for: supplyState)
    }

    var body: some View {
        Menu {
            ForEach(groups.indices, id: \.self) { index in
                Section {
                    ForEach(groups[index]) { action in
                        Button(role: action.isDestructive ? .destructive : nil) {
                            onSelect(action)
                        } label: {
                            Label(action.label, systemImage: action.systemImage)
                        }
                        .accessibilityIdentifier("project-action-\(action.rawValue)")
                    }
                }
            }
        } label: {
            Label("Manage Project", systemImage: "ellipsis.circle")
        }
        .disabled(!isEnabled || groups.isEmpty)
        .accessibilityIdentifier("manage-project-menu")
    }
}
