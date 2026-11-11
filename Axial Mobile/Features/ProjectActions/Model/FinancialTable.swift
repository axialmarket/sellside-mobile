//
//  FinancialTable.swift
//  Axial Mobile
//

import Foundation

/// The Add Historical Metrics editor — add-financial-data-modal.store.ts
/// and its custom-metrics store. Holds raw text per cell; only a table with
/// no conflict is written back to the form (`syncToForm`).
struct FinancialTable: Equatable {
    enum Column: Hashable, Identifiable {
        case year(Int)
        case ltm

        var id: String {
            switch self {
            case .year(let year): "fy-\(year)"
            case .ltm: "ltm"
            }
        }

        var period: String {
            switch self {
            case .year(let year): String(year)
            case .ltm: "ltm"
            }
        }
    }

    struct Cell: Equatable {
        var raw: String = ""
        var error: CellError?
        /// Revenue/EBITDA missing beside a filled partner — only shown once
        /// validation is showing.
        var pairing = false
    }

    struct CustomRow: Equatable, Identifiable {
        let id: String
        var metric: String?
    }

    static let standardMetrics = ["revenue", "ebitda"]
    static let labels = ["revenue": "Revenue", "ebitda": "EBITDA", "gross_profit": "Gross Profit", "capex": "CAPEX"]
    static let actualsLookback = 10
    static let projectedLookahead = 3

    private(set) var columns: [Column]
    private(set) var fiscalYearEnd: Int
    /// metric → column → cell.
    private(set) var cells: [String: [Column: Cell]] = [:]
    private(set) var customRows: [CustomRow]
    private var nextCustomID = 1
    let now: Date
    /// Units for custom metrics, from the catalog.
    private var units: [String: String] = [:]

    // MARK: Load

    /// `fromIntent`: periods into columns, Revenue/EBITDA into the standard
    /// rows, everything else (bar computed margins) into custom rows.
    init(rows: [FinancialRow], fiscalYearEnd: Int?, now: Date, catalog: FinancialCatalog) {
        self.now = now
        self.fiscalYearEnd = fiscalYearEnd ?? 12
        let recent = FiscalCalendar.mostRecentCompletedYear(now: now, fyEndMonth: fiscalYearEnd)
        var columns: Set<Column> = [.year(recent - 2), .year(recent - 1), .year(recent), .ltm, .year(recent + 1)]
        var customOrder: [String] = []
        for type in catalog.types { units[type.key] = type.unit }

        for row in rows {
            let column: Column
            if row.timePeriod == "ltm" { column = .ltm }
            else if let year = row.year { column = .year(year) }
            else { continue }
            columns.insert(column)
            guard let value = row.value, value.isFinite else { continue }
            if ["ebitda_margin", "gross_margin"].contains(row.financialType) { continue }
            if !Self.standardMetrics.contains(row.financialType), !customOrder.contains(row.financialType) {
                customOrder.append(row.financialType)
            }
            // Static: `self` isn't fully initialised yet.
            let unit = Self.unit(for: row.financialType, units: units)
            cells[row.financialType, default: [:]][column] = Cell(raw: FinancialCellRules.edited(value, unit: unit))
        }
        self.columns = Self.chronological(Array(columns), recent: recent)
        customRows = customOrder.map { CustomRow(id: "custom-\($0)", metric: $0) }
        if customRows.isEmpty { customRows = [CustomRow(id: "custom-1", metric: nil)] }
        nextCustomID = 2
        revalidateAll(catalog: catalog)
    }

    var recentYear: Int { FiscalCalendar.mostRecentCompletedYear(now: now, fyEndMonth: fiscalYearEnd) }

    /// FY years ascending, with LTM directly after the last completed one.
    static func chronological(_ columns: [Column], recent: Int) -> [Column] {
        let years = columns.compactMap { if case .year(let y) = $0 { y } else { nil } }.sorted()
        guard columns.contains(.ltm) else { return years.map(Column.year) }
        let before = years.filter { $0 <= recent }.map(Column.year)
        let after = years.filter { $0 > recent }.map(Column.year)
        return before + [.ltm] + after
    }

    func isProjected(_ column: Column) -> Bool {
        if case .year(let year) = column { return year > recentYear }
        return false
    }

    /// LTM and the most recent completed year can't be removed, and carry
    /// the † — one of them needs Revenue and EBITDA.
    func isLocked(_ column: Column) -> Bool {
        column == .ltm || column == .year(recentYear)
    }

    func label(_ column: Column) -> String {
        switch column {
        case .ltm: "LTM"
        case .year(let year): FiscalCalendar.columnLabel(year: year, fyEndMonth: fiscalYearEnd)
        }
    }

    func unit(for metric: String) -> String {
        Self.unit(for: metric, units: units)
    }

    /// Revenue and EBITDA are dollars; custom metrics take the catalog's
    /// unit, defaulting to dollars.
    private static func unit(for metric: String, units: [String: String]) -> String {
        standardMetrics.contains(metric) ? "$" : (units[metric] ?? "$")
    }

    func cell(_ metric: String, _ column: Column) -> Cell {
        cells[metric]?[column] ?? Cell()
    }

    // MARK: Editing

    mutating func setRaw(_ raw: String, metric: String, column: Column) {
        cells[metric, default: [:]][column, default: Cell()].raw = raw
    }

    /// Blur: sanitise, validate, then re-check the column's pairing rules.
    mutating func commit(metric: String, column: Column, catalog: FinancialCatalog) {
        var cell = self.cell(metric, column)
        cell.raw = FinancialCellRules.sanitize(cell.raw, unit: unit(for: metric))
        cells[metric, default: [:]][column] = cell
        revalidate(column: column, catalog: catalog)
        if cells[metric]?[column]?.error == nil, let number = Double(cell.raw),
           Self.standardMetrics.contains(metric) || unit(for: metric) == "$" {
            cells[metric]?[column]?.raw = FinancialCellRules.display(number)
        }
    }

    mutating func setFiscalYearEnd(_ month: Int, catalog: FinancialCatalog) {
        fiscalYearEnd = month
        columns = Self.chronological(columns, recent: recentYear)
        revalidateAll(catalog: catalog)
    }

    /// Years the Add Year menu offers: ten back, three ahead, minus those
    /// already there.
    var addableActualYears: [Int] {
        (0..<Self.actualsLookback).map { recentYear - $0 }.filter { !columns.contains(.year($0)) }
    }

    var addableProjectedYears: [Int] {
        (1...Self.projectedLookahead).map { recentYear + $0 }.filter { !columns.contains(.year($0)) }
    }

    mutating func addYear(_ year: Int, catalog: FinancialCatalog) {
        guard !columns.contains(.year(year)) else { return }
        columns = Self.chronological(columns + [.year(year)], recent: recentYear)
        revalidateAll(catalog: catalog)
    }

    /// Only Revenue/EBITDA count as "has data" for the confirmation — web
    /// quirk: a column with only custom values goes without asking.
    func columnHasData(_ column: Column) -> Bool {
        Self.standardMetrics.contains { Double(cell($0, column).raw) != nil }
    }

    mutating func removeColumn(_ column: Column, catalog: FinancialCatalog) {
        guard !isLocked(column) else { return }
        columns.removeAll { $0 == column }
        for metric in cells.keys { cells[metric]?[column] = nil }
        revalidateAll(catalog: catalog)
    }

    // MARK: Custom metrics

    mutating func addCustomRow() {
        customRows.append(CustomRow(id: "custom-\(nextCustomID)", metric: nil))
        nextCustomID += 1
    }

    func customRowHasValues(_ id: String) -> Bool {
        guard let metric = customRows.first(where: { $0.id == id })?.metric else { return false }
        return columns.contains { !cell(metric, $0).raw.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// A new metric clears the row's values — the unit and rule change.
    mutating func setCustomMetric(_ id: String, to metric: String, catalog: FinancialCatalog) {
        guard let index = customRows.firstIndex(where: { $0.id == id }) else { return }
        if let old = customRows[index].metric { cells[old] = nil }
        customRows[index].metric = metric
        if let type = catalog.type(metric) { units[metric] = type.unit }
        revalidateAll(catalog: catalog)
    }

    /// The last row is reset, not removed.
    mutating func removeCustomRow(_ id: String, catalog: FinancialCatalog) {
        guard let index = customRows.firstIndex(where: { $0.id == id }) else { return }
        if let metric = customRows[index].metric { cells[metric] = nil }
        if customRows.count > 1 { customRows.remove(at: index) }
        else { customRows[index].metric = nil }
        revalidateAll(catalog: catalog)
    }

    func excludedMetrics(forRow id: String, catalog: FinancialCatalog) -> Set<String> {
        catalog.excluded(byOthers: customRows.filter { $0.id != id }.map(\.metric))
    }

    // MARK: Validation

    private mutating func revalidateAll(catalog: FinancialCatalog) {
        for column in columns { revalidate(column: column, catalog: catalog) }
    }

    /// `validateCellValue` per cell, then `validateColumnPairing`.
    private mutating func revalidate(column: Column, catalog: FinancialCatalog) {
        for metric in Self.standardMetrics {
            var cell = self.cell(metric, column)
            cell.error = FinancialCellRules.validateStandard(cell.raw, metric: metric)
            cell.pairing = false
            cells[metric, default: [:]][column] = cell
        }
        let revenue = Double(cell("revenue", column).raw)
        let ebitda = Double(cell("ebitda", column).raw)
        let anyValid = Self.standardMetrics.contains { cell($0, column).error == nil && Double(cell($0, column).raw) != nil }
        if anyValid {
            for metric in Self.standardMetrics where cell(metric, column).raw.isEmpty {
                cells[metric]?[column]?.pairing = true
            }
        }
        if let revenue, cell("revenue", column).error == nil {
            if revenue < 0 {
                cells["revenue"]?[column]?.error = .invalidValue
            } else if revenue > 0, let ebitda, cell("ebitda", column).error == nil, ebitda >= revenue {
                cells["ebitda"]?[column]?.error = .invalidValue
                cells["revenue"]?[column]?.error = .invalidValue
            }
        }
        for row in customRows {
            guard let metric = row.metric, let type = catalog.type(metric) else { continue }
            var cell = self.cell(metric, column)
            cell.error = FinancialCellRules.validate(cell.raw, type: type, revenue: revenue, periodic: true)
            cells[metric, default: [:]][column] = cell
        }
    }

    /// `validateSaveGate`: Revenue and EBITDA, both valid, in the LTM or the
    /// most recent completed year.
    var canSave: Bool {
        [Column.ltm, .year(recentYear)].contains { column in
            Self.standardMetrics.allSatisfy { metric in
                let cell = cell(metric, column)
                return cell.error == nil && Double(cell.raw) != nil
            }
        }
    }

    /// Every cell as if just blurred — for Save tapped with a cell focused.
    mutating func commitAll(catalog: FinancialCatalog) {
        for (metric, byColumn) in cells {
            let unit = unit(for: metric)
            for (column, cell) in byColumn where !cell.raw.isEmpty {
                let sanitized = FinancialCellRules.sanitize(cell.raw, unit: unit)
                cells[metric]?[column]?.raw = sanitized
            }
        }
        revalidateAll(catalog: catalog)
    }

    /// Any `invalid_value` or `out_of_range` — Save stays put while true.
    var hasConflict: Bool {
        cells.values.contains { $0.values.contains { $0.error != nil } }
    }

    /// The red banner above the table, standard rows first, de-duplicated.
    func conflictMessages(catalog: FinancialCatalog) -> [String] {
        var messages: [String] = []
        func add(_ message: String) { if !messages.contains(message) { messages.append(message) } }
        for column in columns {
            for metric in Self.standardMetrics where cell(metric, column).error == .outOfRange {
                add("\(Self.labels[metric]!): \(FinancialCellRules.outOfRangeMessage)")
            }
            let revenue = cell("revenue", column)
            if revenue.error == .invalidValue, let value = Double(revenue.raw), value < 0 {
                add("Revenue must be greater than 0")
            }
            let ebitda = cell("ebitda", column)
            if ebitda.error == .invalidValue, let e = Double(ebitda.raw), let r = Double(revenue.raw), e >= r {
                add("EBITDA must be less than Revenue")
            }
        }
        for row in customRows {
            guard let metric = row.metric else { continue }
            let type = catalog.type(metric)
            let label = catalog.addable.first { $0.key == metric }?.label ?? type?.label ?? "This metric"
            let kinds = Set(columns.compactMap { cell(metric, $0).error })
            for kind in [CellError.invalidValue, .outOfRange] where kinds.contains(kind) {
                add(FinancialCellRules.message(for: kind, type: type, label: label, periodic: true))
            }
        }
        return messages
    }

    // MARK: Payload

    /// Column by column, Revenue then EBITDA; then each custom row across
    /// the columns. `is_estimated` is recomputed from today and FY end.
    var rows: [FinancialRow] {
        var rows: [FinancialRow] = []
        for column in columns {
            for metric in Self.standardMetrics {
                if let row = row(metric, column) { rows.append(row) }
            }
        }
        for custom in customRows {
            guard let metric = custom.metric else { continue }
            for column in columns {
                if let row = row(metric, column) { rows.append(row) }
            }
        }
        return rows
    }

    private func row(_ metric: String, _ column: Column) -> FinancialRow? {
        let raw = cell(metric, column).raw.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let value = FinancialCellRules.stored(raw, unit: unit(for: metric)) else { return nil }
        return FinancialRow(financialType: metric, timePeriod: column.period, isEstimated: isProjected(column), value: value)
    }

    // MARK: Banners

    /// Projections whose year has passed (`rolloverYears`) and a stale LTM.
    static func rollover(rows: [FinancialRow], now: Date, fyEndMonth: Int?) -> (years: [Int], ltm: Bool) {
        let recent = FiscalCalendar.mostRecentCompletedYear(now: now, fyEndMonth: fyEndMonth)
        let years = Set(rows.filter { $0.isEstimated && Self.standardMetrics.contains($0.financialType) }
            .compactMap(\.year).filter { $0 <= recent })
        return (years.sorted(), FiscalCalendar.isLTMRolledOver(rows, now: now))
    }

    /// `staleGapYears`: nothing in the recent year or LTM, and missing years
    /// between the latest filled one and now.
    var staleGapYears: [Int] {
        let recent = recentYear
        if columnHasData(.year(recent)) || columnHasData(.ltm) { return [] }
        let filled = columns.compactMap { column -> Int? in
            if case .year(let year) = column, year < recent, columnHasData(column) { return year }
            return nil
        }
        guard let latest = filled.max(), latest + 1 <= recent - 1 else { return [] }
        return (latest + 1...recent - 1).filter { !columns.contains(.year($0)) }
    }
}
