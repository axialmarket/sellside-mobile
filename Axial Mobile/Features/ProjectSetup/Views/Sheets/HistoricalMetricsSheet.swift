//
//  HistoricalMetricsSheet.swift
//  Axial Mobile
//

import SwiftUI

/// "Add Historical Metrics" — the web's Add Financial Data modal, full
/// screen. The desktop table becomes one card per period (a year reads
/// top to bottom on a phone); metrics are chosen once, above them.
///
/// Like the web, it writes through live: every blur or structural change
/// that leaves no conflict is synced to the form, and autosave takes it
/// from there. Done is refused while anything is invalid; the X clears the
/// invalid cells and leaves.
struct HistoricalMetricsSheet: View {
    @Environment(ProjectSetupSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var table: FinancialTable?
    @State private var baselineRows: [FinancialRow] = []
    @State private var rolloverDismissed = false
    @State private var rollover: (years: [Int], ltm: Bool) = ([], false)
    @State private var pendingRemoval: FinancialTable.Column?
    @State private var pendingMetricRemoval: String?
    @State private var shakeDone = 0
    @FocusState private var focusedCell: CellID?

    private struct CellID: Hashable { let metric: String; let column: FinancialTable.Column }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let table {
                    content(table)
                        .padding(16)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AxialColor.layer2)
            .navigationTitle("Add Historical Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: load)
        .onChange(of: focusedCell) { old, _ in
            if let old { blur(old) }
        }
        .confirmationDialog(removalTitle, isPresented: removalBinding, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let column = pendingRemoval { mutate { $0.removeColumn(column, catalog: session.catalog) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(removalTitle.dropLast()) and all its values?")
        }
        .confirmationDialog(metricRemovalTitle, isPresented: metricRemovalBinding, titleVisibility: .visible) {
            Button(metricRemovalVerb, role: .destructive) {
                if let id = pendingMetricRemoval { mutate { $0.removeCustomRow(id, catalog: session.catalog) } }
            }
            Button("Cancel", role: .cancel) {}
        }
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

            controls(table)

            HStack(spacing: 16) {
                Text("* Required")
                Text("† At least one required (LTM or most recent fiscal year)")
            }
            .font(.caption)
            .foregroundStyle(AxialColor.textSecondary)

            let conflicts = table.conflictMessages(catalog: session.catalog)
            if !conflicts.isEmpty {
                SetupNotice(style: .error, bullets: conflicts)
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

    private func controls(_ table: FinancialTable) -> some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Fiscal Year End", selection: Binding(
                    get: { table.fiscalYearEnd },
                    set: { month in
                        mutate { $0.setFiscalYearEnd(month, catalog: session.catalog) }
                        // Written straight away, conflicts or not.
                        session.form.financials.fiscalYearEnd = month
                    })) {
                    ForEach(1...12, id: \.self) { month in
                        Text(FiscalCalendar.months[month - 1]).tag(month)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fiscal Year End")
                        .font(.caption)
                        .foregroundStyle(AxialColor.textSecondary)
                    HStack(spacing: 4) {
                        Text(FiscalCalendar.months[table.fiscalYearEnd - 1])
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(AxialColor.textPrimary)
                }
            }
            Spacer()
            Menu {
                Section("Actuals") {
                    if table.addableActualYears.isEmpty {
                        Text("All historical years added")
                    }
                    ForEach(table.addableActualYears, id: \.self) { year in
                        Button(String(year)) { mutate { $0.addYear(year, catalog: session.catalog) } }
                    }
                }
                Section("Projected") {
                    if table.addableProjectedYears.isEmpty {
                        Text("All projected years added")
                    }
                    ForEach(table.addableProjectedYears, id: \.self) { year in
                        Button(String(year)) { mutate { $0.addYear(year, catalog: session.catalog) } }
                    }
                }
            } label: {
                Label("Add Year", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// Revenue and EBITDA always; custom metrics chosen here appear in
    /// every period below.
    private func metricsCard(_ table: FinancialTable) -> some View {
        SetupSegment(title: "Metrics") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    TagCapsule(text: "Revenue *", palette: .plain)
                    TagCapsule(text: "EBITDA *", palette: .plain)
                }
                ForEach(table.customRows) { row in
                    customMetricRow(row, table: table)
                }
                let catalog = session.catalog
                let groups = catalog.groupCount(in: catalog.addable)
                if session.catalogFailed {
                    Button {
                        Task { await session.loadCatalog() ; reloadUnits() }
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(catalog.types.isEmpty || (groups > 0 && table.customRows.count >= groups + 1))
                }
            }
        }
    }

    private func customMetricRow(_ row: FinancialTable.CustomRow, table: FinancialTable) -> some View {
        let catalog = session.catalog
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
                            mutate { $0.removeColumn(column, catalog: session.catalog) }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(AxialColor.textSecondary)
                    .accessibilityLabel("Remove \(table.label(column))")
                }
            }
            ForEach(FinancialTable.standardMetrics, id: \.self) { metric in
                cellRow(metric: metric, label: FinancialTable.labels[metric]!, required: true, column: column, table: table)
            }
            ForEach(table.customRows.compactMap(\.metric), id: \.self) { metric in
                let label = session.catalog.addable.first { $0.key == metric }?.label ?? metric
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
        // Pairing and empty required cells only go red once Review has
        // revealed errors and the financials are invalid.
        let financialsInvalid = session.validation.errors[FinancialsForm.Field.financials] != nil
        let requiredEmpty = required && table.isLocked(column) && cell.raw.isEmpty
        let showsError = cell.error != nil
            || (session.showsValidationErrors && financialsInvalid && (cell.pairing || requiredEmpty))
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
                    set: { raw in mutate(sync: false) { $0.setRaw(raw, metric: metric, column: column) } }
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
            SetupNotice(style: .warning, title: "Add your most recent financials",
                        message: "Members evaluate deals on current actuals, and yours are out of date. Add recent years to bring your data up to date.")
            Button {
                mutate { table in for year in gaps { table.addYear(year, catalog: session.catalog) } }
            } label: {
                Label("Add \(gaps.count) Year\(gaps.count == 1 ? "" : "s")", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var rolloverBanner: some View {
        ZStack(alignment: .topTrailing) {
            if !rollover.years.isEmpty, rollover.ltm {
                SetupNotice(style: .info, message: "Some of your figures are out of date, so we've cleared them:",
                            bullets: ["The years entered as projections have passed and are now Actuals columns",
                                      "The LTM data is over a year old",
                                      "Enter the current numbers in the empty fields."])
            } else if rollover.ltm {
                SetupNotice(style: .info, message: "The LTM data is now over a year old. We've cleared it so it reflects current performance. Add the latest LTM numbers.")
            } else {
                SetupNotice(style: .info, message: "The years previously entered as projections have now passed. We've cleared those figures and switched the columns to Actuals. Enter your real numbers for each one.")
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
            Button("Close", systemImage: "xmark") {
                focusedCell = nil
                mutate { $0.clearInvalidCells(catalog: session.catalog) }
                dismiss()
            }
        }
        if session.isAutosaveEnabled {
            ToolbarItem(placement: .topBarTrailing) { AutosaveIndicator() }
        }
        ToolbarItem(placement: .bottomBar) {
            Button("Done") {
                focusedCell = nil
                guard table?.hasConflict != true else {
                    Haptics.error()
                    shakeDone += 1
                    return
                }
                Haptics.success()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AxialColor.brandPrimary)
            .keyframeAnimator(initialValue: 0.0, trigger: shakeDone) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack { for x in [8.0, -8, 6, -6, 0] { LinearKeyframe(x, duration: 0.06) } }
            }
        }
    }

    // MARK: State

    private func load() {
        guard table == nil else { return }
        let financials = session.form.financials
        let intentRows = session.intent["company"]?["financials"]?.array?.compactMap(FinancialRow.init(json:)) ?? []
        rollover = FinancialTable.rollover(rows: intentRows.filter(\.isPeriodic), now: session.context.now,
                                           fyEndMonth: financials.fiscalYearEnd)
        let table = FinancialTable(rows: financials.periodic.rows, fiscalYearEnd: financials.fiscalYearEnd,
                                   now: session.context.now, catalog: session.catalog)
        self.table = table
        baselineRows = table.rows
    }

    private func reloadUnits() {
        table = nil
        load()
    }

    private func blur(_ cell: CellID) {
        mutate { $0.commit(metric: cell.metric, column: cell.column, catalog: session.catalog) }
    }

    /// Applies an edit and — unless it's a keystroke — `syncToForm`.
    private func mutate(sync: Bool = true, _ change: (inout FinancialTable) -> Void) {
        guard var table else { return }
        change(&table)
        self.table = table
        guard sync, !table.hasConflict else { return }
        let rows = table.rows
        // A payload identical to what was loaded is no change at all.
        guard rows != baselineRows || session.form.financials.fiscalYearEnd != table.fiscalYearEnd else { return }
        baselineRows = rows
        session.form.financials.periodic.rows = rows
        session.form.financials.fiscalYearEnd = table.fiscalYearEnd
        session.touch(FinancialsForm.Field.financials)
    }

    private var requestMetricURL: URL { URL(string: "https://form.typeform.com/to/fdq8cvQO")! }

    private var removalTitle: String {
        guard let column = pendingRemoval, let table else { return "" }
        return "Remove \(table.label(column))?"
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var metricRemovalLabel: String {
        guard let id = pendingMetricRemoval, let metric = table?.customRows.first(where: { $0.id == id })?.metric else {
            return "this metric"
        }
        return session.catalog.addable.first { $0.key == metric }?.label ?? "this metric"
    }

    private var metricRemovalVerb: String { (table?.customRows.count ?? 0) > 1 ? "Remove" : "Clear" }

    private var metricRemovalTitle: String { "\(metricRemovalVerb) \(metricRemovalLabel)?" }

    private var metricRemovalBinding: Binding<Bool> {
        Binding(get: { pendingMetricRemoval != nil }, set: { if !$0 { pendingMetricRemoval = nil } })
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
