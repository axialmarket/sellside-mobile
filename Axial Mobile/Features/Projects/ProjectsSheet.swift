//
//  ProjectsSheet.swift
//  Axial Mobile
//

import SwiftUI

/// The sheets the projects list can raise from its bottom toolbar.
enum ProjectsSheet: String, Identifiable, CaseIterable {
    case filter
    case newProject

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filter: "Filter"
        case .newProject: "New Project"
        }
    }

    var systemImage: String {
        switch self {
        case .filter: "line.3.horizontal.decrease"
        case .newProject: "plus"
        }
    }
}

/// Placeholder contents. Each sheet is a real presentation with its own
/// navigation and a large title; what goes under the title comes next.
struct ProjectsSheetView: View {
    let sheet: ProjectsSheet

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Color.clear.frame(height: 1)
            }
            .scrollBounceBehavior(.always, axes: .vertical)
            .background(AxialColor.layer2)
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("projects-sheet-\(sheet.rawValue)")
    }
}

#Preview("Filter") {
    ProjectsSheetView(sheet: .filter)
}

#Preview("New Project") {
    ProjectsSheetView(sheet: .newProject)
}
