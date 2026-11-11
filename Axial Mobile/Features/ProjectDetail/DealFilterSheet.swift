//
//  DealFilterSheet.swift
//  Axial Mobile
//

import SwiftUI

/// The filter sheet behind a member list's bottom-bar button. Edits apply
/// live, as on the projects list and the web's grid column filters.
struct DealFilterSheet: View {
    @Binding var filter: DealFilter
    /// Every member in this list, unsearched — what the options are drawn from.
    let deals: [SellsideDeal]
    /// How many cards the list is showing right now, search included.
    let matchingCount: Int

    @Environment(\.dismiss) private var dismiss

    private var options: DealFilterOptions {
        DealFilterOptions(deals: deals, selected: filter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    ForEach(options.statuses) { option in
                        FilterOptionRow(label: option.label, count: option.count,
                                        isSelected: $filter.statuses.membership(of: option.value))
                            .accessibilityIdentifier("deal-filter-status-\(option.value.rawValue)")
                    }
                }

                Section("Activity") {
                    Toggle("Has New Messages", isOn: $filter.hasNewMessages)
                        .tint(AxialColor.brandPrimary)
                        .accessibilityIdentifier("deal-filter-new-messages")
                }

                Section("Capital Source") {
                    ForEach(options.capitalSources) { option in
                        FilterOptionRow(label: option.label, count: option.count,
                                        isSelected: $filter.capitalSources.membership(of: option.value))
                    }
                }

                Section("Closed Deals") {
                    ForEach(options.closedDeals) { option in
                        FilterOptionRow(label: option.label, count: option.count,
                                        isSelected: $filter.closedDeals.membership(of: option.value))
                    }
                }

                // Up to eighteen types on a big list, so it gets its own page.
                Section {
                    FilterChoiceLink(title: "Company Type", options: options.companyTypes,
                                     selection: $filter.companyTypes)
                        .accessibilityIdentifier("deal-filter-company-type")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AxialColor.layer2)
            .navigationTitle("Filter")
            .navigationSubtitle("\(matchingCount) of \(deals.count) members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        Haptics.selection()
                        filter = DealFilter()
                    }
                    .disabled(!filter.isActive)
                    .accessibilityIdentifier("deal-filter-reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("deal-filter-sheet")
    }
}

#Preview {
    @Previewable @State var filter = DealFilter(statuses: [.sentTeaser])
    let deals: [SellsideDeal] = [
        .init(publicId: "d1", supplyStatus: .sentTeaser, demandAccountCode: "PE", capitalSource: .committed),
        .init(publicId: "d2", supplyStatus: .targetSignedNda, demandAccountCode: "FO"),
        .init(publicId: "d3", supplyStatus: .sentTeaser, demandIsRead: true, newMessageCount: 1),
    ]
    DealFilterSheet(filter: $filter, deals: deals,
                    matchingCount: filter.apply(to: deals, query: "").count)
}
