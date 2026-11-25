//
//  FilterControls.swift
//  Sellside Mobile
//

import SwiftUI

/// One choice a filter sheet can offer: a value, how it reads, and how many
/// items carry it. Shared by the projects and members filters.
struct FilterOption<Value: Hashable>: Identifiable, Equatable {
    let value: Value
    let label: String
    let count: Int

    var id: Value { value }

    /// The value shown beside a pushed choice list's row in a sheet:
    /// "Any", the one label, or "N selected".
    static func summary(of selection: Set<Value>, in options: [FilterOption<Value>]) -> String {
        switch selection.count {
        case 0: "Any"
        case 1: options.first { selection.contains($0.value) }?.label ?? "1 selected"
        default: "\(selection.count) selected"
        }
    }
}

extension Binding {
    /// A Bool binding onto one element's membership in a bound set — what a
    /// tickable row or a toggle needs.
    func membership<Element: Hashable>(of element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool> {
            wrappedValue.contains(element)
        } set: { isOn in
            if isOn {
                wrappedValue.insert(element)
            } else {
                wrappedValue.remove(element)
            }
        }
    }
}

/// One tickable option: label, how many items carry it, a checkmark.
/// The checkmark fades rather than appearing, so the row keeps its identity.
struct FilterOptionRow: View {
    let label: String
    let count: Int
    @Binding var isSelected: Bool

    var body: some View {
        Button {
            Haptics.selection()
            isSelected.toggle()
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(AxialColor.textPrimary)
                Spacer(minLength: 8)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(AxialColor.textPlaceholder)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(AxialColor.brandPrimary)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row in a filter sheet that pushes a searchable multi-select, for
/// options that run too long to list inline.
struct FilterChoiceLink<Value: Hashable>: View {
    let title: String
    let options: [FilterOption<Value>]
    @Binding var selection: Set<Value>

    var body: some View {
        NavigationLink {
            FilterChoiceList(title: title, options: options, selection: $selection)
        } label: {
            LabeledContent(title, value: FilterOption.summary(of: selection, in: options))
        }
        .disabled(options.isEmpty)
    }
}

/// The pushed multi-select behind a `FilterChoiceLink`.
struct FilterChoiceList<Value: Hashable>: View {
    let title: String
    let options: [FilterOption<Value>]
    @Binding var selection: Set<Value>

    @State private var query = ""

    private var visible: [FilterOption<Value>] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.label.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        List {
            ForEach(visible) { option in
                FilterOptionRow(
                    label: option.label, count: option.count,
                    isSelected: $selection.membership(of: option.value)
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(AxialColor.layer2)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    Haptics.selection()
                    selection = []
                }
                .disabled(selection.isEmpty)
            }
        }
    }
}

/// A bottom-bar filter button that fills blue while a filter is applied,
/// the way Mail's does.
///
/// `.borderedProminent` is how a SwiftUI bar item asks for the bar's tinted
/// glass — the bar's own style, not a glass container nested inside it.
///
/// A knowing exception to "don't vary structure": the bar forces a
/// prominent item's icon to white and ignores `.foregroundStyle`, so a
/// prominent style with a clear tint can't pass for the plain state. The swap
/// mostly happens from inside the filter sheet, while the sheet covers the
/// button; a Clear Filters button on an empty state makes it snap instead.
struct FilterToolbarButton: View {
    let activeCount: Int
    let identifier: String
    let action: () -> Void

    private var isActive: Bool { activeCount > 0 }

    var body: some View {
        let value = isActive ? "\(activeCount) applied" : "None applied"
        if isActive {
            base
                .buttonStyle(.borderedProminent)
                .tint(AxialColor.brandPrimary)
                .accessibilityValue(value)
        } else {
            base
                .tint(AxialColor.textPrimary)
                .accessibilityValue(value)
        }
    }

    private var base: some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier(identifier)
    }
}
