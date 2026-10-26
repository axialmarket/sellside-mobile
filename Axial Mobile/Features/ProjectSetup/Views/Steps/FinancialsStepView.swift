//
//  FinancialsStepView.swift
//  Axial Mobile
//

import SwiftUI

/// Financials & KPIs — financials-section.html: Performance Over Time,
/// Current Metrics, Valuation Expectation, Financial Reporting Details.
struct FinancialsStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isEditingHistorical = false
    private typealias F = FinancialsForm.Field

    var body: some View {
        @Bindable var session = session
        let financials = session.form.financials

        performance(financials)
        CurrentMetricsSegment()
        ValuationSegment(valuation: $session.form.financials.valuation)
        reporting($session.form.financials)
    }

    // MARK: Performance Over Time

    private func performance(_ financials: FinancialsForm) -> some View {
        let invalid = session.visibleError(for: F.financials) != nil || session.visibleError(for: F.fiscalYearEnd) != nil
        return SetupSegment(title: "Performance Over Time", isRequired: true,
                            description: "Add Revenue, EBITDA, and other important metrics you want to show year by year.",
                            hasError: session.segmentHasError([F.financials, F.fiscalYearEnd, F.kpis])) {
            Button {
                isEditingHistorical = true
            } label: {
                Label("Add Historical Metrics", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(invalid ? AxialColor.error : AxialColor.brandPrimary)
            .id(F.financials)
            .accessibilityIdentifier("setup-add-historical-metrics")

            if financials.periodic.hasValues {
                FinancialSummaryTable(rows: financials.periodic.rows, catalog: session.catalog)
            }
            if financials.periodic.hasStaleProjection(now: session.context.now) {
                SetupNotice(style: .warning, message: "Please update your expected financials to reflect the actuals from that year.")
            }
            SetupNotice(style: .neutral,
                        message: "Serious buyside members look for complete financials. The more you share, the stronger the responses you'll receive. Don't see a metric you need?")
            Link("Request it here", destination: URL(string: "https://form.typeform.com/to/fdq8cvQO")!)
                .font(.footnote.weight(.medium))
        }
        .fullScreenCover(isPresented: $isEditingHistorical, onDismiss: {
            session.touch(F.financials)
            session.touch(F.fiscalYearEnd)
        }) {
            HistoricalMetricsSheet()
        }
    }

    // MARK: Financial Reporting Details

    private func reporting(_ form: Binding<FinancialsForm>) -> some View {
        let audited = Binding<String?>(get: { form.wrappedValue.audited }, set: { form.wrappedValue.audited = $0 ?? "no" })
        return SetupSegment(title: "Financial Reporting Details") {
            SetupRadioGroup(label: "Have the historical financials been audited?", choices: CompanyBasicsOptions.yesNo,
                            selection: audited, field: "financials.audited")
            if form.wrappedValue.audited == "yes" {
                SetupTextField(label: "By whom?", text: form.auditedBy, field: F.auditedBy, placeholder: "Enter an Auditor")
                    .transition(.opacity)
            }
            SetupRichTextEditor(label: "Financial Commentary", value: form.commentary, field: F.commentary,
                                placeholder: "Feel free to explain any custom metrics or any additional financial information you would like buyside members to know.")
        }
        .animation(.easeOut(duration: 0.2), value: form.wrappedValue.audited)
    }
}

/// `axl-financial-details-cnc`: the read-only table, scrolling sideways.
struct FinancialSummaryTable: View {
    let rows: [FinancialRow]
    let catalog: FinancialCatalog

    private struct Line: Identifiable { let id: String; let label: String; let unit: String }

    private var periods: [String] {
        let withValues = Set(rows.filter { $0.value != nil }.map(\.timePeriod))
        let years = withValues.compactMap(Int.init).sorted()
        let actualYears = years.filter { year in !rows.contains { $0.timePeriod == String(year) && $0.isEstimated } }
        var result = years.map(String.init)
        if withValues.contains("ltm") {
            let index = actualYears.last.flatMap { last in result.firstIndex(of: String(last)) }.map { $0 + 1 } ?? 0
            result.insert("ltm", at: index)
        }
        return result
    }

    private var lines: [Line] {
        var lines = [Line(id: "revenue", label: "Revenue", unit: "$"), Line(id: "ebitda", label: "EBITDA", unit: "$")]
        for (key, label) in [("gross_profit", "Gross Profit"), ("capex", "CAPEX")] where rows.contains(where: { $0.financialType == key && $0.value != nil }) {
            lines.append(Line(id: key, label: label, unit: "$"))
        }
        let shown = Set(lines.map(\.id)).union(["ebitda_margin", "gross_margin"])
        for type in catalog.addable where !shown.contains(type.key) && rows.contains(where: { $0.financialType == type.key && $0.value != nil }) {
            lines.append(Line(id: type.key, label: type.label, unit: type.unit))
        }
        return lines
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(periods, id: \.self) { period in
                        Text(header(period))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AxialColor.textSecondary)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(lines) { line in
                    GridRow {
                        Text(line.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AxialColor.textPrimary)
                            .gridColumnAlignment(.leading)
                        ForEach(periods, id: \.self) { period in
                            Text(FinancialCellRules.summary(value(line.id, period), unit: line.unit))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(AxialColor.textPrimary)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(AxialColor.layer2, in: RoundedRectangle(cornerRadius: 8))
    }

    private func value(_ type: String, _ period: String) -> Double? {
        rows.first { $0.financialType == type && $0.timePeriod == period }?.value
    }

    /// `2024`, `LTM`, `2026E`.
    private func header(_ period: String) -> String {
        let estimated = (rows.first { $0.financialType == "revenue" && $0.timePeriod == period }
            ?? rows.first { $0.timePeriod == period })?.isEstimated == true
        return (period + (estimated ? "e" : "")).uppercased()
    }
}

/// "Current Metrics" — kpi-section: point-in-time metrics, validated on
/// blur, with an error list above the rows.
private struct CurrentMetricsSegment: View {
    @Environment(ProjectSetupSession.self) private var session
    @FocusState private var focused: String?
    @State private var pendingMetricChange: (row: String, metric: String)?
    @State private var pendingRemoval: String?

    var body: some View {
        let financials = session.form.financials
        let catalog = session.catalog
        let errors = financials.kpis.compactMap { row -> String? in
            guard let error = row.error else { return nil }
            let type = row.metric.flatMap(catalog.type)
            let label = row.metric.flatMap { key in catalog.kpi.first { $0.key == key }?.label } ?? "This metric"
            return FinancialCellRules.message(for: error, type: type, label: label, periodic: false)
        }
        SetupSegment(title: "Current Metrics",
                     description: "Add point-in-time metrics that reflect the business today, not tied to a specific year.") {
            if !errors.isEmpty {
                SetupNotice(style: .error, bullets: errors)
            }
            ForEach(financials.kpis) { row in
                kpiRow(row, catalog: catalog)
            }
            let groups = catalog.groupCount(in: catalog.kpi)
            Button {
                session.form.financials.addKPI()
            } label: {
                Label("Add Current Metric", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(groups > 0 && financials.kpis.count >= groups + 1)
        }
        .id(FinancialsForm.Field.kpis)
        .onChange(of: focused) { old, _ in
            if let old { session.form.financials.commitKPI(old, catalog: session.catalog) }
        }
        .confirmationDialog("Change metric?", isPresented: changeBinding, titleVisibility: .visible) {
            Button("Change metric", role: .destructive) {
                if let pending = pendingMetricChange {
                    session.form.financials.setKPIMetric(pending.row, to: pending.metric, catalog: session.catalog)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changing this metric will clear the value you've entered for it. Continue?")
        }
        .confirmationDialog(removalTitle, isPresented: removalBinding, titleVisibility: .visible) {
            Button(removalVerb, role: .destructive) {
                if let id = pendingRemoval { session.form.financials.removeKPI(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(removalVerb) \(removalLabel) and all its values?")
        }
    }

    private func kpiRow(_ row: KPIRow, catalog: FinancialCatalog) -> some View {
        let others = session.form.financials.kpis.filter { $0.id != row.id }.map(\.metric)
        let excluded = catalog.excluded(byOthers: others)
        let options = catalog.kpi.filter { !excluded.contains($0.key) || $0.key == row.metric }
        let type = row.metric.flatMap(catalog.type)
        let unit = type?.unit ?? "$"
        let label = row.metric.flatMap { key in catalog.kpi.first { $0.key == key }?.label }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(options) { option in
                        Button(option.label) { pick(option.key, for: row) }
                    }
                    if options.isEmpty {
                        Link("Request a metric", destination: URL(string: "https://form.typeform.com/to/fdq8cvQO")!)
                    }
                } label: {
                    HStack {
                        Text(label ?? "Select a metric")
                            .foregroundStyle(label == nil ? AxialColor.textPlaceholder : AxialColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                            .foregroundStyle(AxialColor.textSecondary)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AxialColor.border))
                }
                if let metric = row.metric, let description = FinancialCatalog.descriptions[metric] {
                    InfoButton(text: description)
                }
                Button {
                    if row.isBlank { session.form.financials.removeKPI(row.id) } else { pendingRemoval = row.id }
                } label: {
                    Image(systemName: "trash")
                }
                .tint(AxialColor.textSecondary)
                .accessibilityLabel("Remove \(label ?? "metric")")
            }
            if row.metric != nil {
                HStack(spacing: 4) {
                    if unit == "$" { Text("$").foregroundStyle(AxialColor.textSecondary) }
                    TextField("0.0", text: Binding(
                        get: { row.raw },
                        set: { raw in
                            if let index = session.form.financials.kpis.firstIndex(where: { $0.id == row.id }) {
                                session.form.financials.kpis[index].raw = raw
                            }
                        }))
                        .keyboardType(unit == "#" ? .numberPad : .numbersAndPunctuation)
                        .focused($focused, equals: row.id)
                        .monospacedDigit()
                    if unit == "$" { Text("M").foregroundStyle(AxialColor.textSecondary) }
                    if unit == "%" { Text("%").foregroundStyle(AxialColor.textSecondary) }
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(row.error != nil ? AxialColor.errorSubtle : AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(row.error != nil ? AxialColor.error : AxialColor.border, lineWidth: row.error != nil ? 2 : 1))
            }
        }
    }

    private func pick(_ metric: String, for row: KPIRow) {
        guard metric != row.metric else { return }
        if row.metric != nil, !row.isBlank {
            pendingMetricChange = (row.id, metric)
        } else {
            session.form.financials.setKPIMetric(row.id, to: metric, catalog: session.catalog)
        }
    }

    private var changeBinding: Binding<Bool> {
        Binding(get: { pendingMetricChange != nil }, set: { if !$0 { pendingMetricChange = nil } })
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var removalVerb: String { session.form.financials.kpis.count > 1 ? "Remove" : "Clear" }

    private var removalLabel: String {
        guard let id = pendingRemoval,
              let metric = session.form.financials.kpis.first(where: { $0.id == id })?.metric else { return "this metric" }
        return session.catalog.kpi.first { $0.key == metric }?.label ?? "this metric"
    }

    private var removalTitle: String { "\(removalVerb) \(removalLabel)?" }
}

/// "Valuation Expectation": base metric and a min–max multiple. The web's
/// two-handle slider becomes a pair of steppers, 0.5 apart.
private struct ValuationSegment: View {
    @Binding var valuation: ValuationInput
    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        let options = session.catalog.valuation
        VStack(alignment: .leading, spacing: 0) {
            SetupSegment(title: "Valuation Expectation",
                         description: "Share the valuation range you're targeting for this deal.") {
                if valuation.hasInput {
                    Button("Clear") { valuation.clear() }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                SetupMenuPicker(label: "Base Metric",
                                choices: options.map { .init(value: $0.key, label: Self.baseLabel($0.label)) },
                                selection: Binding(get: { valuation.metric },
                                                   set: { valuation.metric = $0; valuation.commitIfValid() }),
                                field: FinancialsForm.Field.valuation, placeholder: "Select a metric")
                HStack(spacing: 12) {
                    multipleField("Min Multiple", value: Binding(
                        get: { valuation.min },
                        set: { valuation.min = $0.map(Self.round); valuation.commitIfValid() }),
                        range: 0...(valuation.max ?? ValuationInput.maxMultiple))
                    multipleField("Max Multiple", value: Binding(
                        get: { valuation.max },
                        set: { valuation.max = $0.map(Self.round); valuation.commitIfValid() }),
                        range: (valuation.min ?? 0)...ValuationInput.maxMultiple)
                }
            }
        }
    }

    private func multipleField(_ label: String, value: Binding<Double?>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SetupFieldLabel(text: label)
            HStack {
                Text(value.wrappedValue.map { "\($0.formatted(.number.precision(.fractionLength(1))))x" } ?? "0.0x")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(value.wrappedValue == nil ? AxialColor.textPlaceholder : AxialColor.textPrimary)
                Spacer()
                Stepper(label, value: Binding(
                    get: { value.wrappedValue ?? range.lowerBound },
                    set: { value.wrappedValue = $0 }
                ), in: range, step: 0.5)
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AxialColor.border))
        }
    }

    /// "EBITDA Multiple" → "EBITDA".
    static func baseLabel(_ label: String) -> String {
        label.hasSuffix(" Multiple") ? String(label.dropLast(" Multiple".count)) : label
    }

    /// Rounded to the tenth, as typed values are.
    static func round(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}
