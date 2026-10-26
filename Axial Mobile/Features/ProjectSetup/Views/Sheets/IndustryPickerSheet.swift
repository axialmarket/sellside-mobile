//
//  IndustryPickerSheet.swift
//  Axial Mobile
//

import SwiftUI

/// "Industry Selection" — the web's full-screen industry modal, at its
/// mobile-web shape (the results column; filters and cart fold into the
/// search field and the bottom bar).
///
/// Edits a draft: Finish Selecting commits it, Cancel throws it away.
struct IndustryPickerSheet: View {
    @Binding var selection: [IndustrySelection]

    @Environment(APIClient.self) private var apiClient
    @Environment(ProjectSetupSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var draft: [IndustrySelection] = []
    @State private var groups: [IndustryTaxonomy.Group] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var expandedGroups: Set<String> = []
    @State private var expandedNodes: Set<String> = []
    @State private var isShowingCart = false
    @State private var isShowingEmptyError = false
    @State private var isConfirmingDiscard = false

    var body: some View {
        NavigationStack {
            List {
                if let loadError {
                    ContentUnavailableView {
                        Label("Could not fetch all industries.", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else if !isLoading, groups.isEmpty {
                    ContentUnavailableView {
                        Label("Your search does not match any industries.", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try a different search keyword.")
                    }
                } else {
                    Section {
                        ForEach(groups) { group in
                            groupRows(group)
                        }
                    } header: {
                        Text("\(totalCount) \(totalCount == 1 ? "industry" : "industries")")
                            .contentTransition(.numericText())
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if isLoading, groups.isEmpty, loadError == nil {
                    ProgressView("Loading…")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Filter results by keyword")
            .navigationTitle("Industry Selection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        if draft != selection { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isShowingCart = true
                    } label: {
                        Label("\(draft.count) Selected", systemImage: "cart")
                            .labelStyle(.titleAndIcon)
                            .contentTransition(.numericText())
                    }
                    .tint(AxialColor.textPrimary)
                    .disabled(draft.isEmpty)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Finish Selecting") {
                        guard !draft.isEmpty else {
                            Haptics.error()
                            isShowingEmptyError = true
                            return
                        }
                        Haptics.success()
                        selection = draft
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AxialColor.success)
                    .opacity(draft.isEmpty ? 0.6 : 1)
                }
            }
            .sheet(isPresented: $isShowingCart) {
                SelectedIndustriesSheet(selection: $draft)
            }
            .alert("Error", isPresented: $isShowingEmptyError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please select specific industries from the results section in order to finish adding industries.")
            }
            .confirmationDialog("Discard your industry changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Selecting", role: .cancel) {}
            }
        }
        .onAppear { draft = selection }
        .task(id: query) {
            // `keyword-filter`: 300 ms debounce.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private var totalCount: Int { groups.map(\.industryCount).reduce(0, +) }

    // MARK: Rows

    @ViewBuilder
    private func groupRows(_ group: IndustryTaxonomy.Group) -> some View {
        let isExpanded = expandedGroups.contains(group.id) || !query.isEmpty
        Button {
            withAnimation(.snappy) {
                if expandedGroups.contains(group.id) { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
            }
        } label: {
            HStack {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
        }
        if isExpanded {
            ForEach(group.trees) { tree in
                nodeRows(tree, group: group, depth: 0)
            }
        }
    }

    private func nodeRows(_ node: IndustryTaxonomy.Node, group: IndustryTaxonomy.Group, depth: Int) -> AnyView {
        let key = "\(group.id):\(node.id)"
        let isExpanded = expandedNodes.contains(key) || !query.isEmpty
        let selectable = IndustrySelectionRules.isSelectable(node)
        let checked = IndustrySelectionRules.isChecked(node, in: group, selected: draft)
        let partial = !checked && IndustrySelectionRules.isPartial(node, in: group, selected: draft)
        return AnyView(Group {
            HStack(spacing: 10) {
                if selectable {
                    Button {
                        Haptics.selection()
                        draft = IndustrySelectionRules.toggle(node, in: group, selected: draft)
                    } label: {
                        Image(systemName: checked ? "checkmark.square.fill" : partial ? "minus.square.fill" : "square")
                            .foregroundStyle(checked || partial ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(checked ? "Deselect \(node.name)" : "Select \(node.name)")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textPrimary)
                    if !node.children.isEmpty {
                        Text("\(node.leafCount) industries | \(node.height) levels deep")
                            .font(.caption)
                            .foregroundStyle(AxialColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if !node.children.isEmpty {
                    Button {
                        withAnimation(.snappy) {
                            if expandedNodes.contains(key) { expandedNodes.remove(key) } else { expandedNodes.insert(key) }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(AxialColor.textPlaceholder)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse \(node.name)" : "Expand \(node.name)")
                }
            }
            .padding(.leading, CGFloat(depth) * 18)
            if isExpanded {
                ForEach(node.children) { child in
                    nodeRows(child, group: group, depth: depth + 1)
                }
            }
        })
    }

    // MARK: Data

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let response: IndustryTaxonomy.Response = try await apiClient.get(
                "taxonomy",
                query: IndustryTaxonomy.query(sourceType: query.isEmpty ? "cache" : "intent",
                                              sourceID: query.isEmpty ? "root" : session.intentId,
                                              keyword: query),
                headers: IndustryTaxonomy.headers
            )
            groups = IndustryTaxonomy.sorted(response.searchResults)
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

/// The cart: "Selected Industries" with Clear All.
private struct SelectedIndustriesSheet: View {
    @Binding var selection: [IndustrySelection]
    @Environment(\.dismiss) private var dismiss

    private var grouped: [(title: String, items: [IndustrySelection])] {
        Dictionary(grouping: selection) { "\($0.vertical):\($0.activity)" }
            .map { _, items in
                let first = items[0]
                let title = "\(IndustryTaxonomy.verticals[first.vertical] ?? "") + \(IndustryTaxonomy.activities[first.activity] ?? "")"
                return (title, items.sorted { $0.name < $1.name })
            }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.title) { group in
                    Section("\(group.title) (\(group.items.count))") {
                        ForEach(group.items) { item in
                            Text(item.name)
                                .swipeActions {
                                    Button("Remove", role: .destructive) {
                                        selection.removeAll { $0.id == item.id }
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Selected Industries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") { selection = []; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
