//
//  SetupPickers.swift
//  Axial Mobile
//

import SwiftUI

/// The web's filterable `axl-dropdown`, as a searchable sheet — for lists
/// too long for a menu (250 countries, 51 states).
struct SetupSearchPicker<Value: Hashable>: View {
    let title: String
    let choices: [SetupChoice<Value>]
    let selection: Value?
    var searchPrompt = "Search"
    let onSelect: (Value) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [SetupChoice<Value>] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return choices }
        return choices.filter { $0.label.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { choice in
                Button {
                    Haptics.selection()
                    onSelect(choice.value)
                    dismiss()
                } label: {
                    HStack {
                        Text(choice.label).foregroundStyle(AxialColor.textPrimary)
                        Spacer()
                        if choice.value == selection {
                            Image(systemName: "checkmark").foregroundStyle(AxialColor.brandPrimary)
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView("No results found", systemImage: "magnifyingglass")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: searchPrompt)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// A row that shows the current choice and opens a `SetupSearchPicker`.
struct SetupSearchPickerRow<Value: Hashable>: View {
    let label: String?
    let choices: [SetupChoice<Value>]
    @Binding var selection: Value?
    let field: SetupFieldKey
    var placeholder = "Select"
    var searchPrompt = "Search"

    @Environment(ProjectSetupSession.self) private var session
    @State private var isPresented = false

    var body: some View {
        SetupPickerRow(
            label: label,
            field: field,
            summary: [],
            placeholder: choices.first { $0.value == selection }?.label ?? placeholder,
            hasValue: selection != nil
        ) {
            isPresented = true
        }
        .sheet(isPresented: $isPresented, onDismiss: { session.touch(field) }) {
            SetupSearchPicker(title: label ?? placeholder, choices: choices, selection: selection,
                              searchPrompt: searchPrompt) { selection = $0 }
        }
    }
}

/// Multi-select from a list, in a sheet — the web's multiselects and the
/// member pickers. Edits apply live.
struct SetupMultiPicker<Value: Hashable>: View {
    let title: String
    let choices: [SetupChoice<Value>]
    @Binding var selection: [Value]
    var searchable = false

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [SetupChoice<Value>] {
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

/// Removable chips with an optional Clear All — the industry and
/// suppression chip rows.
struct SetupChipList: View {
    let items: [(id: String, label: String)]
    var palette: TagPalette = .blue
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button {
                    Haptics.selection()
                    onRemove(item.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(item.label).lineLimit(1)
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.background, in: Capsule())
                    .foregroundStyle(palette.foreground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.label)")
            }
        }
    }
}
