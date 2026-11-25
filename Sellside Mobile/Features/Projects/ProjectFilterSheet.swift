//
//  ProjectFilterSheet.swift
//  Sellside Mobile
//

import SwiftUI

/// The filter sheet behind the projects list's bottom-bar button. Edits
/// apply live, the way the web grid's column filters do — the list behind
/// is already showing the result when the sheet comes down.
struct ProjectFilterSheet: View {
    @Binding var filter: ProjectFilter
    /// Every project we hold, unsearched — what the options are drawn from.
    let projects: [SellsideProject]
    /// How many cards the list is showing right now, search included.
    let matchingCount: Int

    @Environment(\.dismiss) private var dismiss

    private var options: ProjectFilterOptions {
        ProjectFilterOptions(projects: projects, selected: filter)
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                activitySection
                createdSection
                peopleAndIndustrySection
            }
            .scrollContentBackground(.hidden)
            .background(AxialColor.layer2)
            .navigationTitle("Filter")
            .navigationSubtitle("\(matchingCount) of \(projects.count) projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        Haptics.selection()
                        filter = ProjectFilter()
                    }
                    .disabled(!filter.isActive)
                    .accessibilityIdentifier("project-filter-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("projects-sheet-filter")
    }

    private var statusSection: some View {
        Section("Status") {
            ForEach(options.statuses) { option in
                FilterOptionRow(
                    label: option.label, count: option.count,
                    isSelected: membership(\.statuses, option.value)
                )
                .accessibilityIdentifier("project-filter-status-\(option.value.rawValue)")
            }
        }
    }

    private var activitySection: some View {
        Section("Activity") {
            ForEach(ProjectFilter.Activity.allCases) { activity in
                Toggle(activity.label, isOn: membership(\.activity, activity))
                    .tint(AxialColor.brandPrimary)
                    .accessibilityIdentifier("project-filter-activity-\(activity.rawValue)")
            }
        }
    }

    private var createdSection: some View {
        Section("Created") {
            Picker("Created", selection: $filter.created) {
                Text("Any Time").tag(ProjectFilter.CreatedWindow?.none)
                ForEach(ProjectFilter.CreatedWindow.allCases) { window in
                    Text(window.label).tag(Optional(window))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("project-filter-created")
        }
    }

    /// Contacts and sectors can run long on a big account, so each gets its
    /// own pushed list rather than stretching the sheet.
    private var peopleAndIndustrySection: some View {
        Section {
            FilterChoiceLink(title: "Contact", options: options.contacts, selection: $filter.contacts)
                .accessibilityIdentifier("project-filter-contact")
            FilterChoiceLink(title: "Industry", options: options.sectors, selection: $filter.sectors)
                .accessibilityIdentifier("project-filter-industry")
        }
    }

    /// A Bool binding onto one value's membership in one of the filter's sets.
    private func membership<Value: Hashable>(
        _ keyPath: WritableKeyPath<ProjectFilter, Set<Value>>, _ value: Value
    ) -> Binding<Bool> {
        $filter[dynamicMember: keyPath].membership(of: value)
    }
}

#Preview {
    @Previewable @State var filter = ProjectFilter(statuses: [.inMarket], activity: [.interested])
    let projects: [SellsideProject] = [
        .mock(name: "Neptune"),
        .mock(name: "Atlas", state: .draft, sectors: ["Healthcare"]),
        .mock(name: "Orion", state: .underLoi, interested: 0),
    ]
    ProjectFilterSheet(
        filter: $filter, projects: projects,
        matchingCount: filter.apply(to: projects).count
    )
}
