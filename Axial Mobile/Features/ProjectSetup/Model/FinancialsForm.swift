//
//  FinancialsForm.swift
//  Axial Mobile
//

import Foundation

/// The Financials & KPIs step — financials-step/step-definition.ts.
struct FinancialsForm: Equatable {
    /// `financials`: periodic rows, written by the historical-metrics sheet.
    var periodic: PeriodicFinancials
    /// `kpis`: the Current Metrics rows as edited. Only valid, blurred values
    /// reach the payload.
    var kpis: [KPIRow]
    var valuation: ValuationInput
    /// `fiscal-year-end`, 1–12. Nil until chosen — it's a required field.
    var fiscalYearEnd: Int?
    var audited: String
    var auditedBy: String
    var commentary: RichTextValue
    /// KPI units, captured when a metric is picked, so the payload can scale
    /// dollars without the catalog in hand.
    var kpiUnits: [String: String] = [:]
    private var nextKPIID = 1

    init(intent: JSONValue, now: Date) {
        let company = intent["company"]
        let rows = company?["financials"]?.array?.compactMap(FinancialRow.init(json:)) ?? []
        var periodicRows = rows.filter(\.isPeriodic)
        // `clearRolledOverLtmValues`: a stale LTM starts out empty.
        if FiscalCalendar.isLTMRolledOver(periodicRows, now: now) {
            periodicRows = periodicRows.map { row in
                guard row.timePeriod == "ltm" else { return row }
                var cleared = row
                cleared.value = nil; cleared.minValue = nil; cleared.maxValue = nil
                return cleared
            }
        }
        periodic = PeriodicFinancials(rows: periodicRows)

        // One row per KPI type, in payload order; the catalog isn't needed to
        // seed them, only to label and validate.
        var seen: Set<String> = []
        kpis = rows.filter(\.isKPI).compactMap { row -> KPIRow? in
            guard seen.insert(row.financialType).inserted, let value = row.value else { return nil }
            return KPIRow(id: "kpi-\(row.financialType)", metric: row.financialType, raw: String(value), error: nil,
                          committed: String(value))
        }
        if kpis.isEmpty { kpis = [KPIRow(id: "kpi-new-1", metric: nil, raw: "", error: nil)] }
        nextKPIID = 2

        let valuationRow = rows.first(where: \.isValuation)
        valuation = ValuationInput(metric: valuationRow?.financialType, min: valuationRow?.minValue,
                                   max: valuationRow?.maxValue, committed: valuationRow)
        fiscalYearEnd = company?["fiscal_year_end_month"]?.int
        audited = company?["is_audited"]?.bool == true ? "yes" : "no"
        auditedBy = company?["auditing_firm_name"]?.string ?? ""
        commentary = RichTextValue(html: intent["financial_commentary"]?.string ?? "")
    }

    /// Re-expresses saved dollar KPIs in millions once the catalog says
    /// which are dollars — hydration waits for the catalog on the web too.
    mutating func applyCatalog(_ catalog: FinancialCatalog) {
        for index in kpis.indices {
            guard let metric = kpis[index].metric, let type = catalog.type(metric), kpiUnits[metric] == nil else { continue }
            kpiUnits[metric] = type.unit
            if type.unit == "$", let value = Double(kpis[index].raw) {
                kpis[index].raw = FinancialCellRules.edited(value, unit: "$")
                kpis[index].committed = kpis[index].committed.flatMap(Double.init).map { FinancialCellRules.edited($0, unit: "$") }
            }
            kpis[index].error = FinancialCellRules.validate(kpis[index].raw, type: type, revenue: nil, periodic: false)
            if kpis[index].error != nil { kpis[index].committed = nil }
        }
    }

    // MARK: KPI editing

    mutating func addKPI() {
        kpis.append(KPIRow(id: "kpi-new-\(nextKPIID)", metric: nil, raw: "", error: nil))
        nextKPIID += 1
    }

    /// Picking a different metric clears the value — the unit and rule change.
    mutating func setKPIMetric(_ id: String, to metric: String, catalog: FinancialCatalog) {
        guard let index = kpis.firstIndex(where: { $0.id == id }) else { return }
        kpis[index].metric = metric
        kpis[index].raw = ""
        kpis[index].error = nil
        kpis[index].committed = nil
        kpiUnits[metric] = catalog.type(metric)?.unit ?? "$"
    }

    /// Blur: sanitise, validate, keep the error until the next blur.
    mutating func commitKPI(_ id: String, catalog: FinancialCatalog) {
        guard let index = kpis.firstIndex(where: { $0.id == id }), let metric = kpis[index].metric else { return }
        let unit = catalog.type(metric)?.unit ?? kpiUnits[metric] ?? "$"
        kpiUnits[metric] = unit
        kpis[index].raw = FinancialCellRules.sanitize(kpis[index].raw, unit: unit)
        if let type = catalog.type(metric) {
            kpis[index].error = FinancialCellRules.validate(kpis[index].raw, type: type, revenue: nil, periodic: false)
        }
        if kpis[index].error == nil, unit == "$", let number = Double(kpis[index].raw) {
            kpis[index].raw = FinancialCellRules.display(number)
        }
        kpis[index].committed = kpis[index].error == nil && !kpis[index].isBlank ? kpis[index].raw : nil
    }

    /// The last row is reset rather than removed — there's always one.
    mutating func removeKPI(_ id: String) {
        if kpis.count > 1 {
            kpis.removeAll { $0.id == id }
        } else if let index = kpis.firstIndex(where: { $0.id == id }) {
            kpis[index] = KPIRow(id: kpis[index].id, metric: nil, raw: "", error: nil)
        }
    }

    var committedKPIs: [FinancialRow] {
        kpis.compactMap { row in
            guard let metric = row.metric, let committed = row.committed else { return nil }
            // No unit yet means the catalog hasn't landed, and the text is
            // still the saved value — pass it through unscaled.
            let value = kpiUnits[metric].map { FinancialCellRules.stored(committed, unit: $0) } ?? Double(committed)
            guard let value else { return nil }
            return FinancialRow(financialType: metric, timePeriod: "na", isEstimated: false, value: value)
        }
    }

    // MARK: Payload

    /// `extractFinancialsFromFormForModal`.
    func write(into intent: inout JSONValue) {
        intent.set(.bool(audited == "yes"), at: "company.is_audited")
        // Kept even when audited is "no" — web quirk.
        intent.set(.string(orNull: auditedBy.isEmpty ? nil : auditedBy), at: "company.auditing_firm_name")
        intent.set(.number(orNull: fiscalYearEnd.map(Double.init)), at: "company.fiscal_year_end_month")
        intent.set(.string(orNull: commentary.isEmpty ? nil : commentary.html), at: "financial_commentary")
        let rows = periodic.rows + committedKPIs + (valuation.committed.map { [$0] } ?? [])
        intent.set(.array(rows.map(\.json)), at: "company.financials")
    }

    // MARK: Validation

    enum Field {
        static let financials: SetupFieldKey = "financials.financials"
        static let fiscalYearEnd: SetupFieldKey = "financials.fiscal-year-end"
        static let kpis: SetupFieldKey = "financials.kpis"
        static let auditedBy: SetupFieldKey = "financials.audited_by"
        static let commentary: SetupFieldKey = "financials.financial_commentary"
        static let valuation: SetupFieldKey = "financials.valuation"
    }

    func validate(now: Date, into v: inout StepValidationBuilder) {
        v.require(Field.financials, satisfied: periodic.isComplete(now: now, fyEndMonth: fiscalYearEnd), error: "")
        v.require(Field.fiscalYearEnd, satisfied: fiscalYearEnd != nil, error: "Required")
        // `financialsOutOfRange` blocks the step; an invalid value only
        // blocks autosave.
        if kpis.contains(where: { $0.error == .outOfRange }) {
            v.groupError(Field.kpis, "")
        }
    }
}
