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

    var id: String { "\(projectId)-\(action.rawValue)" }
}

/// The status changes for a project, grouped the way the web separates them
/// (`ProjectAction.menu(for:)`). Shared by the dashboard's Manage Project
/// menu, a project card's context menu and its swipe action, so all three
/// offer the same items in the same order.
struct ProjectStatusMenuItems: View {
    let groups: [[ProjectAction]]
    /// A header over the first group. It goes on that group rather than an
    /// outer `Section`, because a menu flattens nested sections and the
    /// separators between the groups would be lost.
    var title: String?
    let onSelect: (ProjectAction) -> Void

    var body: some View {
        ForEach(groups.indices, id: \.self) { index in
            Section {
                ForEach(groups[index]) { action in
                    // No destructive role, even for On Hold and Deal is
                    // Dead: both can be undone with Return to Market.
                    Button {
                        onSelect(action)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
                    .accessibilityIdentifier("project-action-\(action.rawValue)")
                }
            } header: {
                if index == 0, let title {
                    Text(title)
                }
            }
        }
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
    func projectStatusFlow(
        _ request: Binding<ProjectStatusRequest?>,
        performingId: Binding<String?>
    ) -> some View {
        modifier(ProjectStatusFlow(request: request, performingId: performingId))
    }
}

private struct ProjectStatusFlow: ViewModifier {
    @Binding var request: ProjectStatusRequest?
    @Binding var performingId: String?

    @Environment(ProjectDashboardStore.self) private var store
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                confirming?.action.label ?? "",
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: confirming
            ) { request in
                Button(request.action.label) {
                    perform(request)
                }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text(request.action.confirmationMessage)
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

    private var confirming: ProjectStatusRequest? {
        request?.action.needsCounterparty == false ? request : nil
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

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { request = nil } })
    }

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
