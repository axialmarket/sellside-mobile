//
//  CounterpartySheet.swift
//  Axial Mobile
//

import SwiftUI

/// Asks who the deal is with before a project goes under LOI or closes — the
/// mobile form of fe-app's `axl-update-intent-with-counterparty-modal`.
///
/// Web uses a typeahead over the contacted companies that also accepts free
/// text, and works out afterwards whether what you typed matched an option.
/// A picker plus an explicit "outside Axial" row says the same thing without
/// the guessing, and produces the same payload.
///
/// Only the sourcing question is required, matching the web's validators: you
/// can close a project without naming the counterparty.
struct CounterpartySheet: View {
    let action: ProjectAction
    let options: [CounterpartyOption]
    let onSubmit: (CounterpartyInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sourcedViaAxial: Bool?
    @State private var selection: CounterpartySelection = .unspecified
    @State private var customName = ""

    var body: some View {
        NavigationStack {
            Form {
                sourcingSection
                counterpartySection
                if action == .closed { closedBenefitsSection }
            }
            .navigationTitle(action.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") { submit() }
                        .disabled(sourcedViaAxial == nil)
                        .accessibilityIdentifier("counterparty-submit")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sourcingSection: some View {
        Section {
            Picker("Sourcing", selection: $sourcedViaAxial) {
                Text("Via Axial").tag(Bool?.some(true))
                Text("Outside of Axial").tag(Bool?.some(false))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("counterparty-sourcing")
        } header: {
            Text("How did you source the buyside party?")
        } footer: {
            if sourcedViaAxial == nil {
                Text("Required.")
            }
        }
    }

    private var counterpartySection: some View {
        Section {
            Picker("Counterparty", selection: $selection) {
                Text("Not specified").tag(CounterpartySelection.unspecified)
                ForEach(options) { option in
                    Text(option.name).tag(CounterpartySelection.member(option.accountId))
                }
                Text("Someone outside Axial").tag(CounterpartySelection.outsideAxial)
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("counterparty-picker")

            if selection == .outsideAxial {
                TextField("Company name", text: $customName)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("counterparty-custom-name")
            }
        } header: {
            Text("Counterparty")
        } footer: {
            if options.isEmpty {
                Text("No contacted companies on this project yet.")
            }
        }
    }

    private var closedBenefitsSection: some View {
        Section("On closing") {
            Label("Eligible for Axial's investment banking league tables", systemImage: "trophy")
            Label("Elevated ranking in Axial's member directory", systemImage: "arrow.up.circle")
            Label("The Axial verified Closed Deal Badge", systemImage: "checkmark.seal")
        }
        .font(.subheadline)
        .foregroundStyle(AxialColor.textSecondary)
    }

    private func submit() {
        guard let sourcedViaAxial else { return }
        onSubmit(CounterpartyInfo.make(
            selection: selection,
            customName: customName,
            sourcedViaAxial: sourcedViaAxial
        ))
        dismiss()
    }
}

#Preview("Under LOI") {
    CounterpartySheet(
        action: .underLoi,
        options: [
            CounterpartyOption(accountId: "a1", name: "Bluewater Capital"),
            CounterpartyOption(accountId: "a2", name: "Harbor Point Partners"),
        ],
        onSubmit: { _ in }
    )
}

#Preview("Closed, no deals") {
    CounterpartySheet(action: .closed, options: [], onSubmit: { _ in })
}
