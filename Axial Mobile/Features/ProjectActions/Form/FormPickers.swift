//
//  FormPickers.swift
//  Axial Mobile
//

import SwiftUI

/// Multi-select from a list, in a sheet — the web's multiselects and the
/// member pickers. Edits apply live.
struct FormMultiPicker<Value: Hashable>: View {
    let title: String
    let choices: [FormChoice<Value>]
    @Binding var selection: [Value]
    var searchable = false

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [FormChoice<Value>] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return choices }
        return choices.filter { $0.label.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { choice in
                let isOn = selection.contains(choice.value)
                Button {
                    Haptics.selection()
                    if isOn { selection.removeAll { $0 == choice.value } } else { selection.append(choice.value) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isOn ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.label).foregroundStyle(AxialColor.textPrimary)
                            if let detail = choice.detail {
                                Text(detail).font(.caption).foregroundStyle(AxialColor.textSecondary)
                            }
                        }
                    }
                }
            }
            .modifier(OptionalSearch(isEnabled: searchable, query: $query))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { selection = [] }
                        .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct OptionalSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        } else {
            content
        }
    }
}
