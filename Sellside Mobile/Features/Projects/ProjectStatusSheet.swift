//
//  ProjectStatusSheet.swift
//  Sellside Mobile
//

import SwiftUI

/// A project card's swiped Status, as a sheet: the project and where it
/// stands, then its status changes grouped at the web's separators
/// (`ProjectAction.menu(for:)`), the same items as the dashboard's Update
/// Status menu. Rows read like the member actions sheet's — title leading,
/// icon trailing.
///
/// Picking a status hands it back and closes the sheet; the caller runs it
/// once the sheet is gone, so the confirmation or counterparty sheet that
/// follows never presents over this one on its way out.
struct ProjectStatusSheet: View {
    let project: SellsideProject
    let onSelect: (ProjectAction) -> Void

    @Environment(\.dismiss) private var dismiss

    private var groups: [[ProjectAction]] { ProjectAction.menu(for: project.supplyState) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

                ForEach(groups.indices, id: \.self) { index in
                    Section {
                        ForEach(groups[index]) { action in
                            Button {
                                Haptics.selection()
                                onSelect(action)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(action.label)
                                    Spacer(minLength: 8)
                                    Image(systemName: action.systemImage)
                                        .frame(width: 24)
                                }
                                .foregroundStyle(AxialColor.textPrimary)
                            }
                            .accessibilityIdentifier("project-status-\(action.rawValue)")
                        }
                    }
                }
            }
            .listSectionSpacing(14)
            .navigationTitle("Update Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .tint(AxialColor.textPrimary)
        .accessibilityIdentifier("project-status-sheet")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.internalName)
                    .font(.headline)
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(2)
                if !project.sectors.isEmpty {
                    Text(project.sectorNames)
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            StatusTag(state: project.supplyState)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ProjectStatusSheet(project: .mock()) { _ in }
            .presentationDetents([.medium, .large])
    }
}
