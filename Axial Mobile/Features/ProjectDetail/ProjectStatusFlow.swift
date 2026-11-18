//
//  ProjectStatusFlow.swift
//  Axial Mobile
//

import SwiftUI

/// A status change someone has picked for a project, on its way through the
/// confirmation or the counterparty sheet.
struct ProjectStatusRequest: Identifiable, Equatable {
    let projectId: String
    let action: ProjectAction
    /// The view its confirmation opens from (`Confirmation`): the project's
    /// card, the Manage Project menu, the action item. `screen` is the
    /// fallback, attached to the whole screen.
    var anchor = Self.screen

    var id: String { "\(projectId)-\(action.rawValue)" }

    static let screen = "status-screen"
    static let manageMenu = "status-manage-menu"
    static let actionItem = "status-action-item"
}

// MARK: - Status menus
//
// Every Update Status menu — a project's or a deal's, from a toolbar, a card,
// a context menu or the bulk bar — is built from one of the two item lists
// below, so they all read alike:
//
// - Each item is an icon and a label, both in the text colour. The lists set
//   their own tint, so a menu inside a brand-tinted stack or a tinted button
//   doesn't turn its icons blue.
// - Groups follow the web's separators, as sections.
// - When the list is the whole menu, its first group is headed "Update
//   Status" (`title`). Nested under an "Update Status" item, the submenu's
//   own title does that job, so `title` is left off.

/// The status changes for a project, grouped the way the web separates them
/// (`ProjectAction.menu(for:)`). Shared by the dashboard's Manage Project
/// menu, the action item's Update Status menu, a project card's context menu.
struct ProjectStatusMenuItems: View {
    let groups: [[ProjectAction]]
    /// A header over the first group — see the note above.
    var title: String?
    let onSelect: (ProjectAction) -> Void

    var body: some View {
        StatusMenuSections(groups: groups, title: title) { action in
            Button {
                onSelect(action)
            } label: {
                Label(action.label, systemImage: action.systemImage)
            }
            .accessibilityIdentifier("project-action-\(action.rawValue)")
        }
    }
}

/// A deal's status changes — `updateDealStatusOptions`, grouped at the web's
/// separators. The card menu, the deal screen's menu and footer, and the
/// bulk bar (which passes its own, shorter groups).
struct DealStatusMenuItems: View {
    var groups: [[DealStatusUpdateOption]] = DealStatusUpdateOption.groups
    var title: String?
    let onSelect: (DealStatusUpdateOption) -> Void

    var body: some View {
        StatusMenuSections(groups: groups, title: title) { option in
            Button {
                onSelect(option)
            } label: {
                Label(option.label, systemImage: option.systemImage)
            }
            .accessibilityIdentifier("deal-status-\(option.rawValue)")
        }
    }
}

/// The shared shape: a section per group, the header on the first, and the
/// text colour as the tint.
private struct StatusMenuSections<Item: Hashable, Row: View>: View {
    let groups: [[Item]]
    let title: String?
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ForEach(groups.indices, id: \.self) { index in
            Section {
                ForEach(groups[index], id: \.self) { item in
                    row(item)
                }
            } header: {
                if index == 0, let title {
                    Text(title)
                }
            }
        }
        .tint(AxialColor.textPrimary)
    }
}

extension View {
    /// Carries a picked status change through to the API: a confirmation for
    /// most, the counterparty sheet for Under LOI and Closed, then
    /// `ProjectDashboardStore.perform`, which patches the dashboard and the
    /// projects list from the response. An error is reported in an alert.
    ///
    /// `performingId` is the project being updated while the request runs,
    /// so the caller can show progress where the change was asked for.
    ///
    /// The confirmation goes out through `confirmation`, so it opens from
    /// the view named by the request's `anchor`; the screen carries the
    /// fallback.
    func projectStatusFlow(
        _ request: Binding<ProjectStatusRequest?>,
        performingId: Binding<String?>,
        confirmation: Binding<Confirmation?>
    ) -> some View {
        modifier(ProjectStatusFlow(request: request, performingId: performingId, confirmation: confirmation))
    }
}

private struct ProjectStatusFlow: ViewModifier {
    @Binding var request: ProjectStatusRequest?
    @Binding var performingId: String?
    @Binding var confirmation: Confirmation?

    @Environment(ProjectDashboardStore.self) private var store
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .confirmation($confirmation, anchor: ProjectStatusRequest.screen)
            .onChange(of: request) { _, request in
                guard let request, !request.action.needsCounterparty else { return }
                confirmation = Confirmation(
                    anchor: request.anchor, title: request.action.label,
                    message: request.action.confirmationMessage, confirm: request.action.label,
                    isDestructive: false) { perform(request) }
            }
            // Confirmed or cancelled, the request is done with.
            .onChange(of: confirmation == nil) { _, isGone in
                if isGone, request?.action.needsCounterparty == false { request = nil }
            }
            .sheet(item: counterpartyBinding) { request in
                // Opened from the projects list, the dashboard may not be
                // loaded yet, and its deals are where the options come from.
                CounterpartySheet(
                    action: request.action,
                    options: store.dashboard(for: request.projectId)?.counterpartyOptions ?? [],
                    isLoadingOptions: store.dashboard(for: request.projectId) == nil
                ) { counterparty in
                    perform(request, counterparty: counterparty)
                }
                .task { await store.loadIfNeeded(id: request.projectId) }
            }
            .alert(
                "Couldn't update the project",
                isPresented: errorBinding,
                presenting: error
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
    }

    private func perform(_ request: ProjectStatusRequest, counterparty: CounterpartyInfo? = nil) {
        performingId = request.projectId
        Task {
            do {
                try await store.perform(request.action, on: request.projectId, counterparty: counterparty)
                Haptics.success()
            } catch {
                Haptics.error()
                self.error = error.localizedDescription
            }
            performingId = nil
        }
    }

    // MARK: - Presentation bindings

    private var counterpartyBinding: Binding<ProjectStatusRequest?> {
        Binding(
            get: { request?.action.needsCounterparty == true ? request : nil },
            set: { if $0 == nil { request = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
}
