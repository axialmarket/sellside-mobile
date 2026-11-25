//
//  StaleFinancialsSheet.swift
//  Sellside Mobile
//

import SwiftUI

/// Resolves "Update Stale Financials": the web's Add Historical Metrics
/// modal on its own, full screen. The desktop table becomes one card per
/// period (a year reads top to bottom on a phone); metrics are chosen once,
/// above them.
///
/// Projections for years that have closed open empty — the rollover
/// banner's "we've cleared those figures" — so the member enters actuals.
/// Save writes the periodic rows back beside the KPI and valuation rows;
/// once no past-year projection is left, the action item resolves itself.
struct StaleFinancialsSheet: View {
    let projectId: String

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(APIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    @State private var intent: JSONValue?
    @State private var loadError: String?
    @State private var catalog: FinancialCatalog = .empty
    @State private var catalogFailed = false
    @State private var table: FinancialTable?
    @State private var baselineRows: [FinancialRow] = []
    @State private var baselineFiscalYearEnd = 12
    @State private var rolloverDismissed = false
    @State private var rollover: (years: [Int], ltm: Bool) = ([], false)
    @State private var pendingRemoval: FinancialTable.Column?
    @State private var pendingMetricRemoval: String?
    @State private var shakeSave = 0
    @State private var attemptedSave = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedCell: CellID?

    private struct CellID: Hashable { let metric: String; let column: FinancialTable.Column }

    private var now: Date { .now }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let table {
                    content(table)
                        .padding(16)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't load the financials", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Update Financials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .task { await load() }
        .onChange(of: focusedCell) { old, _ in
            if let old { blur(old) }
        }
        .alert("Couldn't save the financials", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        ), presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ table: FinancialTable) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Provide values for at least the last 12 months (LTM) or most recent fiscal year. Additional periods increase buyer interest.")
                .font(.subheadline)
                .foregroundStyle(AxialColor.textSecondary)

            if !table.staleGapYears.isEmpty {
                staleBanner(table.staleGapYears)
            }
            if (!rollover.years.isEmpty || rollover.ltm), !rolloverDismissed {
                rolloverBanner
            }

            HStack(spacing: 16) {
                Text("* Required")
                Text("† At least one required (LTM or most recent fiscal year)")
            }
            .font(.caption)
            .foregroundStyle(AxialColor.textSecondary)

            let conflicts = table.conflictMessages(catalog: catalog)
            if !conflicts.isEmpty {
                FormNotice(style: .error, bullets: conflicts)
                    .transition(.opacity)
            }

            metricsCard(table)

            ForEach(table.columns) { column in
                columnCard(column, table: table)
            }
        }
        .animation(.easeOut(duration: 0.2), value: table.columns)
        .animation(.easeOut(duration: 0.2), value: table.hasConflict)
    }

    /// Fiscal Year End — moves the column labels, the locked years and the
    /// "Actuals"/"Projected" tags.
    private var fiscalYearMenu: some View {
        Menu {
            Picker("Fiscal Year End", selection: Binding(
                get: { table?.fiscalYearEnd ?? 12 },
                set: { month in mutate { $0.setFiscalYearEnd(month, catalog: catalog) } })) {
                ForEach(1...12, id: \.self) { month in
                    Text(FiscalCalendar.months[month - 1]).tag(month)
                }
            }
        } label: {
            Label("FY ends \(FiscalCalendar.months[(table?.fiscalYearEnd ?? 12) - 1].prefix(3))", systemImage: "calendar")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("Fiscal Year End")
    }

    /// Add Year: ten years back, three ahead, minus those already shown.
    private var addYearMenu: some View {
        Menu {
            Section("Actuals") {
                if table?.addableActualYears.isEmpty ?? true {
                    Text("All historical years added")
                }
                ForEach(table?.addableActualYears ?? [], id: \.self) { year in
                    Button(String(year)) { mutate { $0.addYear(year, catalog: catalog) } }
                }
            }
            Section("Projected") {
                if table?.addableProjectedYears.isEmpty ?? true {
                    Text("All projected years added")
                }
                ForEach(table?.addableProjectedYears ?? [], id: \.self) { year in
                    Button(String(year)) { mutate { $0.addYear(year, catalog: catalog) } }
                }
            }
        } label: {
            Label("Add Year", systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
        }
    }

    /// Revenue and EBITDA always; custom metrics chosen here appear in
    /// every period below.
    private func metricsCard(_ table: FinancialTable) -> some View {
        FormSegment(title: "Metrics") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    TagCapsule(text: "Revenue *", palette: .plain)
                    TagCapsule(text: "EBITDA *", palette: .plain)
                }
                ForEach(table.customRows) { row in
                    customMetricRow(row, table: table)
                }
                let catalog = catalog
                let groups = catalog.groupCount(in: catalog.addable)
                if catalogFailed {
                    Button {
                        Task { await loadCatalog(); rebuild() }
                    } label: {
                        Label("Couldn't load metrics — Retry", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        mutate { $0.addCustomRow() }
                    } label: {
                        Label("Add Metric", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(catalog.types.isEmpty || (groups > 0 && table.customRows.count >= groups + 1))
                }
            }
        }
    }

    private func customMetricRow(_ row: FinancialTable.CustomRow, table: FinancialTable) -> some View {
        let catalog = catalog
        let excluded = table.excludedMetrics(forRow: row.id, catalog: catalog)
        let options = catalog.addable.filter { !excluded.contains($0.key) || $0.key == row.metric }
        let label = row.metric.flatMap { key in catalog.addable.first { $0.key == key }?.label }
        return HStack(spacing: 8) {
            Menu {
                ForEach(options) { type in
                    Button(type.label) { mutate { $0.setCustomMetric(row.id, to: type.key, catalog: catalog) } }
                }
                if options.isEmpty {
                    Link("Request a metric", destination: requestMetricURL)
                }
            } label: {
                HStack {
                    Text(label ?? "Select a metric")
                        .foregroundStyle(label == nil ? AxialColor.textPlaceholder : AxialColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                        .foregroundStyle(AxialColor.textSecondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AxialColor.border))
            }
            if let metric = row.metric, let description = FinancialCatalog.descriptions[metric] {
                InfoButton(text: description)
            }
            Button {
                if table.customRowHasValues(row.id) {
                    pendingMetricRemoval = row.id
                } else {
                    mutate { $0.removeCustomRow(row.id, catalog: catalog) }
                }
            } label: {
                Image(systemName: "trash")
            }
            .tint(AxialColor.textSecondary)
            // Opens from this metric's trash button, not the sheet.
            .confirmationDialog(metricRemovalTitle, isPresented: metricRemovalBinding(for: row.id),
                                titleVisibility: .visible) {
                Button(metricRemovalVerb, role: .destructive) {
                    mutate { $0.removeCustomRow(row.id, catalog: catalog) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .accessibilityLabel("Remove \(label ?? "metric")")
        }
    }

    private func columnCard(_ column: FinancialTable.Column, table: FinancialTable) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TagCapsule(text: table.isProjected(column) ? "Projected" : "Actuals",
                           palette: table.isProjected(column) ? .purple : .plain)
                Text(table.label(column) + (table.isLocked(column) ? " †" : ""))
                    .font(.headline)
                    .foregroundStyle(AxialColor.textPrimary)
                Spacer()
                if !table.isLocked(column) {
                    Button {
                        if table.columnHasData(column) {
                            pendingRemoval = column
                        } else {
                            mutate { $0.removeColumn(column, catalog: catalog) }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(AxialColor.textSecondary)
                    // Opens from this year's trash button, not the sheet.
                    .confirmationDialog(removalTitle, isPresented: removalBinding(for: column),
                                        titleVisibility: .visible) {
                        Button("Remove", role: .destructive) {
                            mutate { $0.removeColumn(column, catalog: catalog) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("\(removalTitle.dropLast()) and all its values?")
                    }
                    .accessibilityLabel("Remove \(table.label(column))")
                }
            }
            ForEach(FinancialTable.standardMetrics, id: \.self) { metric in
                cellRow(metric: metric, label: FinancialTable.labels[metric]!, required: true, column: column, table: table)
            }
            ForEach(table.customRows.compactMap(\.metric), id: \.self) { metric in
                let label = catalog.addable.first { $0.key == metric }?.label ?? metric
                cellRow(metric: metric, label: label, required: false, column: column, table: table)
            }
        }
        .padding(16)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AxialColor.border))
    }

    private func cellRow(metric: String, label: String, required: Bool,
                         column: FinancialTable.Column, table: FinancialTable) -> some View {
        let cell = table.cell(metric, column)
        let unit = table.unit(for: metric)
        let id = CellID(metric: metric, column: column)
        // Pairing and empty required cells only go red once Save has been
        // tried and the save gate fails — the web's reveal-on-review.
        let requiredEmpty = required && table.isLocked(column) && cell.raw.isEmpty
        let showsError = cell.error != nil
            || (attemptedSave && !table.canSave && (cell.pairing || requiredEmpty))
        let isNegative = cell.raw.hasPrefix("-") && cell.error == nil
        return HStack(spacing: 10) {
            HStack(spacing: 2) {
                Text(label)
                if required { Text("*").foregroundStyle(AxialColor.errorText) }
            }
            .font(.subheadline)
            .foregroundStyle(AxialColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if unit == "$" { Text("$").foregroundStyle(AxialColor.textSecondary) }
                TextField("0.0", text: Binding(
                    get: { cell.raw },
                    set: { raw in mutate { $0.setRaw(raw, metric: metric, column: column) } }
                ))
                .keyboardType(unit == "#" ? .numberPad : .numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focusedCell, equals: id)
                .foregroundStyle(isNegative ? AxialColor.errorText : AxialColor.textPrimary)
                if unit == "$" { Text("M").foregroundStyle(AxialColor.textSecondary) }
                if unit == "%" { Text("%").foregroundStyle(AxialColor.textSecondary) }
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 150)
            .background(showsError ? AxialColor.errorSubtle : AxialColor.layer2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(showsError ? AxialColor.error : AxialColor.border, lineWidth: showsError ? 2 : 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(table.label(column))")
    }

    // MARK: Banners

    private func staleBanner(_ gaps: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FormNotice(style: .warning, title: "Add your most recent financials",
                        message: "Members evaluate deals on current actuals, and yours are out of date. Add recent years to bring your data up to date.")
            Button {
                mutate { table in for year in gaps { table.addYear(year, catalog: catalog) } }
            } label: {
                Label("Add \(gaps.count) Year\(gaps.count == 1 ? "" : "s")", systemImage: "plus")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var rolloverBanner: some View {
        ZStack(alignment: .topTrailing) {
            if !rollover.years.isEmpty, rollover.ltm {
                FormNotice(style: .info, message: "Some of your figures are out of date, so we've cleared them:",
                            bullets: ["The years entered as projections have passed and are now Actuals columns",
                                      "The LTM data is over a year old",
                                      "Enter the current numbers in the empty fields."])
            } else if rollover.ltm {
                FormNotice(style: .info, message: "The LTM data is now over a year old. We've cleared it so it reflects current performance. Add the latest LTM numbers.")
            } else {
                FormNotice(style: .info, message: "The years previously entered as projections have now passed. We've cleared those figures and switched the columns to Actuals. Enter your real numbers for each one.")
            }
            Button {
                withAnimation { rolloverDismissed = true }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).padding(10)
            }
            .tint(AxialColor.textSecondary)
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) {
                focusedCell = nil
                if hasChanges { isConfirmingDiscard = true } else { dismiss() }
            }
            .disabled(isSaving)
            // Anchored to the button, so it grows out of the ✕.
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm) {
                Task { await save() }
            } label: {
                if isSaving { ProgressView() } else { Label("Save", systemImage: "checkmark") }
            }
            .tint(AxialColor.brandPrimary)
            .disabled(table == nil || isSaving)
            .keyframeAnimator(initialValue: 0.0, trigger: shakeSave) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack { for x in [8.0, -8, 6, -6, 0] { LinearKeyframe(x, duration: 0.06) } }
            }
            .accessibilityIdentifier("stale-financials-save")
        }
        // The table's own controls ride in the bar — two glass capsules,
        // always in reach while the cards scroll beneath.
        ToolbarItem(placement: .bottomBar) {
            fiscalYearMenu
                .disabled(table == nil)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            addYearMenu
                .disabled(table == nil)
        }
    }

    // MARK: State

    private var hasChanges: Bool {
        guard let table else { return false }
        return table.rows != baselineRows || table.fiscalYearEnd != baselineFiscalYearEnd
    }

    private func load() async {
        loadError = nil
        do {
            let intent = try await store.rawProject(id: projectId)
            self.intent = intent
            await loadCatalog()
            rebuild()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// `GET /metadata/financial-types` — needed for custom metric rows.
    private func loadCatalog() async {
        catalogFailed = false
        do {
            let response: FinancialCatalog.Response = try await apiClient.get("metadata/financial-types")
            catalog = FinancialCatalog(response)
        } catch {
            catalogFailed = true
        }
    }

    private func rebuild() {
        guard let intent else { return }
        let fyEnd = intent["company"]?["fiscal_year_end_month"]?.int
        let saved = intent["company"]?["financials"]?.array?.compactMap(FinancialRow.init(json:)) ?? []
        rollover = FinancialTable.rollover(rows: saved.filter(\.isPeriodic), now: now, fyEndMonth: fyEnd)
        let table = FinancialTable(rows: StaleFinancials.editableRows(intent: intent, now: now),
                                   fiscalYearEnd: fyEnd, now: now, catalog: catalog)
        self.table = table
        // Diffed against what was *saved*, so the cleared projections count
        // as an edit: saving them empty is a real change.
        baselineRows = saved.filter(\.isPeriodic)
        baselineFiscalYearEnd = fyEnd ?? 12
    }

    private func blur(_ cell: CellID) {
        mutate { $0.commit(metric: cell.metric, column: cell.column, catalog: catalog) }
    }

    private func mutate(_ change: (inout FinancialTable) -> Void) {
        guard var table else { return }
        change(&table)
        self.table = table
    }

    /// Refused, with a shake, while anything is invalid or neither the LTM
    /// nor the most recent year has Revenue and EBITDA (`validateSaveGate`).
    private func save() async {
        focusedCell = nil
        guard let intent, var table else { return }
        table.commitAll(catalog: catalog)
        self.table = table
        attemptedSave = true
        guard !table.hasConflict, table.canSave else {
            Haptics.error()
            shakeSave += 1
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let patch = StaleFinancials.patch(over: intent, periodic: table.rows, fiscalYearEnd: table.fiscalYearEnd)
            try await store.updateProject(id: projectId, patch: patch)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            saveError = error.localizedDescription
        }
    }

    private var requestMetricURL: URL { URL(string: "https://form.typeform.com/to/fdq8cvQO")! }

    private var removalTitle: String {
        guard let column = pendingRemoval, let table else { return "" }
        return "Remove \(table.label(column))?"
    }

    private func removalBinding(for column: FinancialTable.Column) -> Binding<Bool> {
        Binding(get: { pendingRemoval == column }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var metricRemovalLabel: String {
        guard let id = pendingMetricRemoval, let metric = table?.customRows.first(where: { $0.id == id })?.metric else {
            return "this metric"
        }
        return catalog.addable.first { $0.key == metric }?.label ?? "this metric"
    }

    private var metricRemovalVerb: String { (table?.customRows.count ?? 0) > 1 ? "Remove" : "Clear" }

    private var metricRemovalTitle: String { "\(metricRemovalVerb) \(metricRemovalLabel)?" }

    private func metricRemovalBinding(for id: String) -> Binding<Bool> {
        Binding(get: { pendingMetricRemoval == id }, set: { if !$0 { pendingMetricRemoval = nil } })
    }
}

/// A small ⓘ that shows its text in a popover — the web's tooltips.
struct InfoButton: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(AxialColor.textPlaceholder)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
        .popover(isPresented: $isShowing) {
            Text(text)
                .font(.footnote)
                .padding(14)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}
