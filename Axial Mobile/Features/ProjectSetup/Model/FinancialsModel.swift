//
//  FinancialsModel.swift
//  Axial Mobile
//

import Foundation

/// One row of `company.financials` — the flat shape the current web reads
/// and writes (`FinancialRow`, financials.interfaces.ts): one row per
/// metric and period. `"na"` periods are KPIs or the valuation multiple.
struct FinancialRow: Equatable, Hashable {
    var financialType: String
    var timePeriod: String
    var isEstimated: Bool
    var value: Double?
    var minValue: Double?
    var maxValue: Double?
    /// Read-only, epoch ms; drives the LTM rollover.
    var updatedAt: Double?

    init(financialType: String, timePeriod: String, isEstimated: Bool = false,
         value: Double? = nil, minValue: Double? = nil, maxValue: Double? = nil, updatedAt: Double? = nil) {
        self.financialType = financialType
        self.timePeriod = timePeriod
        self.isEstimated = isEstimated
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.updatedAt = updatedAt
    }

    init?(json: JSONValue) {
        guard let type = json["financial_type"]?.string, let period = json["time_period"]?.string else { return nil }
        self.init(financialType: type, timePeriod: period,
                  isEstimated: json["is_estimated"]?.bool ?? false,
                  value: json["value"]?.number, minValue: json["min_value"]?.number,
                  maxValue: json["max_value"]?.number, updatedAt: json["updated_at"]?.number)
    }

    /// What's sent back: `updated_at` and `yy_growth` are the server's.
    var json: JSONValue {
        var object: [String: JSONValue] = [
            "financial_type": .string(financialType),
            "time_period": .string(timePeriod),
            "is_estimated": .bool(isEstimated),
        ]
        if minValue != nil || maxValue != nil {
            object["min_value"] = .number(orNull: minValue)
            object["max_value"] = .number(orNull: maxValue)
        } else {
            object["value"] = .number(orNull: value)
        }
        return .object(object)
    }

    var isValuation: Bool { timePeriod == "na" && (minValue != nil || maxValue != nil) }
    var isPeriodic: Bool { timePeriod != "na" }
    var isKPI: Bool { timePeriod == "na" && !isValuation }
    var year: Int? {
        guard timePeriod.count == 4, timePeriod.allSatisfy(\.isNumber) else { return nil }
        return Int(timePeriod)
    }
}

// MARK: - Fiscal calendar

enum FiscalCalendar {
    static let months = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]

    /// `mostRecentCompletedFyYear`: a fiscal year ending in month `fyEnd`
    /// counts as completed once that month is behind us.
    static func mostRecentCompletedYear(now: Date, fyEndMonth: Int?, calendar: Calendar = .current) -> Int {
        let fyEnd = fyEndMonth ?? 12
        let parts = calendar.dateComponents([.year, .month], from: now)
        let year = parts.year ?? 2000
        return (parts.month ?? 1) > fyEnd ? year : year - 1
    }

    /// `"Dec 2025"`.
    static func columnLabel(year: Int, fyEndMonth: Int?) -> String {
        let month = months[((fyEndMonth ?? 12) - 1).clamped(to: 0...11)].prefix(3)
        return "\(month) \(year)"
    }

    /// `LTM_ROLLOVER_THRESHOLD_MONTHS`: an LTM saved more than 13 months ago
    /// is out of date and is cleared on load.
    static func isLTMRolledOver(_ rows: [FinancialRow], now: Date, calendar: Calendar = .current) -> Bool {
        let ltm = rows.filter { $0.timePeriod == "ltm" }
        guard let stamp = (ltm.first { $0.financialType == "revenue" } ?? ltm.first)?.updatedAt, stamp > 0,
              let threshold = calendar.date(byAdding: .month, value: -13, to: now) else { return false }
        return Date(timeIntervalSince1970: stamp / 1000) < threshold
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

// MARK: - Periodic financials

/// The step's `financials` control: the periodic rows, written by the Add
/// Historical Metrics sheet.
struct PeriodicFinancials: Equatable {
    var rows: [FinancialRow]

    func value(_ type: String, _ period: String) -> Double? {
        rows.first { $0.financialType == type && $0.timePeriod == period }?.value
    }

    /// `validateFinancialsComplete`: Revenue and EBITDA in the LTM or in the
    /// most recent completed fiscal year. Zero counts only for EBITDA.
    func isComplete(now: Date, fyEndMonth: Int?) -> Bool {
        let recent = String(FiscalCalendar.mostRecentCompletedYear(now: now, fyEndMonth: fyEndMonth))
        return ["ltm", recent].contains { period in
            guard let revenue = value("revenue", period), revenue != 0 else { return false }
            return value("ebitda", period) != nil
        }
    }

    /// The `financialsMinMax` rule autosave checks: a column with negative
    /// Revenue, or with EBITDA at or above a positive Revenue.
    var hasMinMaxConflict: Bool {
        Set(rows.map(\.timePeriod)).contains { period in
            guard let revenue = value("revenue", period) else { return false }
            if revenue < 0 { return true }
            if revenue > 0, let ebitda = value("ebitda", period), ebitda >= revenue { return true }
            return false
        }
    }

    var hasValues: Bool { rows.contains { ($0.value ?? 0) != 0 } }

    /// Distinct periods with a value — "3 Years of Financials".
    var periodCount: Int { Set(rows.filter { $0.value != nil }.map(\.timePeriod)).count }

    /// A projection whose year has passed — "Please update your expected
    /// financials to reflect the actuals from that year."
    func hasStaleProjection(now: Date, calendar: Calendar = .current) -> Bool {
        let year = calendar.component(.year, from: now)
        return rows.contains { $0.isEstimated && ($0.year ?? .max) < year }
    }
}

// MARK: - Catalog

/// `GET /metadata/financial-types` — `DomFinancialType`.
struct FinancialType: Decodable, Equatable, Identifiable {
    let key: String
    let label: String
    let uom: String
    let canBeNonPeriodic: Bool
    let isComputed: Bool
    let sortOrder: Double
    let minAllowed: Double?
    let maxAllowed: Double?
    let isMinInclusive: Bool
    let isWholeNumber: Bool
    let isRevenueConstrained: Bool
    let hasRange: Bool

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, uom
        case canBeNonPeriodic = "can_sellside_be_non_periodic"
        case isComputed = "is_computed"
        case sortOrder = "sort_order"
        case minAllowed = "min_allowed"
        case maxAllowed = "max_allowed"
        case isMinInclusive = "is_min_inclusive"
        case isWholeNumber = "is_whole_number"
        case isRevenueConstrained = "is_revenue_constrained"
        case hasRange = "has_range"
    }

    init(key: String, label: String, uom: String = "dollars", canBeNonPeriodic: Bool = false,
         isComputed: Bool = false, sortOrder: Double = 0, minAllowed: Double? = nil, maxAllowed: Double? = nil,
         isMinInclusive: Bool = true, isWholeNumber: Bool = false, isRevenueConstrained: Bool = false,
         hasRange: Bool = false) {
        self.key = key; self.label = label; self.uom = uom; self.canBeNonPeriodic = canBeNonPeriodic
        self.isComputed = isComputed; self.sortOrder = sortOrder; self.minAllowed = minAllowed
        self.maxAllowed = maxAllowed; self.isMinInclusive = isMinInclusive; self.isWholeNumber = isWholeNumber
        self.isRevenueConstrained = isRevenueConstrained; self.hasRange = hasRange
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? key
        uom = (try? c.decodeIfPresent(String.self, forKey: .uom)) ?? "dollars"
        canBeNonPeriodic = (try? c.decodeIfPresent(Bool.self, forKey: .canBeNonPeriodic)) ?? false
        isComputed = (try? c.decodeIfPresent(Bool.self, forKey: .isComputed)) ?? false
        sortOrder = (try? c.decodeIfPresent(Double.self, forKey: .sortOrder)) ?? 0
        minAllowed = try? c.decodeIfPresent(Double.self, forKey: .minAllowed)
        maxAllowed = try? c.decodeIfPresent(Double.self, forKey: .maxAllowed)
        isMinInclusive = (try? c.decodeIfPresent(Bool.self, forKey: .isMinInclusive)) ?? true
        isWholeNumber = (try? c.decodeIfPresent(Bool.self, forKey: .isWholeNumber)) ?? false
        isRevenueConstrained = (try? c.decodeIfPresent(Bool.self, forKey: .isRevenueConstrained)) ?? false
        hasRange = (try? c.decodeIfPresent(Bool.self, forKey: .hasRange)) ?? false
    }

    /// `$`, `%` or `#`.
    var unit: String {
        switch uom {
        case "pct": "%"
        case "qty": "#"
        default: "$"
        }
    }
}

/// The catalog as both the sheet and the KPI list use it.
struct FinancialCatalog: Equatable {
    var types: [FinancialType]
    var exclusions: [[String]]

    static let empty = FinancialCatalog(types: [], exclusions: [])

    struct Response: Decodable {
        let types: [FinancialType]
        let mutualExclusions: [[String]]?

        enum CodingKeys: String, CodingKey {
            case types
            case mutualExclusions = "mutual_exclusions"
        }
    }

    init(types: [FinancialType], exclusions: [[String]]) {
        self.types = types
        self.exclusions = exclusions
    }

    init(_ response: Response) {
        self.init(types: response.types, exclusions: response.mutualExclusions ?? [])
    }

    func type(_ key: String) -> FinancialType? { types.first { $0.key == key } }

    /// `buildAddableCatalog`: custom rows in the historical sheet.
    var addable: [FinancialType] {
        Self.withUnitLabels(types.filter { !["revenue", "ebitda"].contains($0.key) && !$0.isComputed && !$0.hasRange }
            .sorted { $0.sortOrder < $1.sortOrder })
    }

    /// `buildKpiCatalog`: point-in-time metrics.
    var kpi: [FinancialType] {
        Self.withUnitLabels(types.filter { $0.canBeNonPeriodic && !["revenue", "ebitda"].contains($0.key) && !$0.hasRange }
            .sorted { $0.sortOrder < $1.sortOrder })
    }

    /// `valuationTypes`, labelled without the trailing " Multiple".
    var valuation: [FinancialType] {
        types.filter(\.hasRange).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Keys a row can't take because another row (or its $/% partner) has
    /// them. `excludedKeysByRow`.
    func excluded(byOthers others: [String?]) -> Set<String> {
        var result: Set<String> = []
        for key in others.compactMap({ $0 }) {
            result.insert(key)
            for group in exclusions where group.contains(key) { result.formUnion(group) }
        }
        return result
    }

    /// How many distinct metric choices exist once $/% pairs collapse —
    /// `distinctMetricGroupCount`, which caps how many rows can be added.
    func groupCount(in catalog: [FinancialType]) -> Int {
        let keys = Set(catalog.map(\.key))
        var seen: Set<String> = []
        var groups = 0
        for type in catalog where !seen.contains(type.key) {
            groups += 1
            var stack = [type.key]
            while let key = stack.popLast() {
                guard seen.insert(key).inserted else { continue }
                for group in exclusions where group.contains(key) {
                    stack.append(contentsOf: group.filter { !seen.contains($0) && keys.contains($0) })
                }
            }
        }
        return groups
    }

    /// `appendUnitToSharedLabels`: "Recurring Revenue ($)" / "(%)".
    private static func withUnitLabels(_ types: [FinancialType]) -> [FinancialType] {
        let counts = Dictionary(grouping: types, by: \.label).mapValues(\.count)
        return types.map { type in
            guard (counts[type.label] ?? 0) > 1 else { return type }
            return FinancialType(key: type.key, label: "\(type.label) (\(type.unit))", uom: type.uom,
                                 canBeNonPeriodic: type.canBeNonPeriodic, isComputed: type.isComputed,
                                 sortOrder: type.sortOrder, minAllowed: type.minAllowed, maxAllowed: type.maxAllowed,
                                 isMinInclusive: type.isMinInclusive, isWholeNumber: type.isWholeNumber,
                                 isRevenueConstrained: type.isRevenueConstrained, hasRange: type.hasRange)
        }
    }

    /// `METRIC_DESCRIPTIONS` — FE-only tooltips.
    static let descriptions: [String: String] = [
        "capex": "Capital expenditures — the funds the business spends on acquiring or maintaining fixed assets.",
        "customer_count": "The total number of distinct active customers the business currently serves.",
        "gross_profit": "Revenue minus the direct costs of producing goods or services (cost of goods sold).",
        "net_income": "Total profit left over after subtracting all expenses, taxes, and costs from total revenue.",
        "owner_comp_addbacks": "The owner's salary, personal expenses, and any one-time or non-recurring costs.",
        "contracted_revenue_dollars": "Revenue that is legally committed under a signed agreement for a defined period.",
        "contracted_revenue_percent": "The share of total revenue that is legally committed under a signed agreement for a defined period.",
        "recurring_revenue_dollars": "Revenue the business can reliably expect to collect again without having to win a new sale.",
        "recurring_revenue_percent": "The percentage of revenue the business can reliably expect to collect again without having to win a new sale.",
        "subscription_revenue_dollars": "Revenue generated from customers who pay a recurring fee at a fixed cadence (monthly, quarterly, or annually) in exchange for continued access to a product or service.",
        "subscription_revenue_percent": "The share of revenue generated from customers who pay a recurring fee at a fixed cadence (monthly, quarterly, or annually) in exchange for continued access to a product or service.",
        "sde": "Net income added back with the owner's full compensation and any personal expenses run through the business.",
        "location_count": "The number of distinct physical locations from which the business operates.",
        "customer_retention_rate": "The percentage of customers who continue doing business with the company over a given period.",
        "backlog_pipeline_value": "The total dollar value of confirmed orders or committed work not yet recognized as revenue.",
        "payroll_pct_revenue": "Total payroll costs as a percentage of revenue, reflecting the business's labor intensity.",
        "operating_income": "Earnings from core business operations before interest and taxes (EBIT).",
        "interest_expense": "The cost of debt — interest paid on outstanding loans and other borrowed capital.",
        "adjusted_ebitda": "EBITDA adjusted for non-recurring, one-time, or non-cash items to reflect normalized earnings.",
        "top_1_customer_concentration": "The percentage of total annual revenue that comes from the single largest customer.",
        "top_5_customer_concentration": "The percentage of total annual revenue that comes from the top 5 largest customers.",
        "top_10_customer_concentration": "The percentage of total annual revenue that comes from the top 10 largest customers.",
    ]
}

// MARK: - Cell rules

/// `CellErrorKind`.
enum CellError: String, Equatable {
    case invalidValue = "invalid_value"
    case outOfRange = "out_of_range"
}

enum FinancialCellRules {
    static let range: ClosedRange<Double> = -999...999
    static let outOfRangeMessage = "Values must be between -999 and 999 (in millions)"

    /// money-input `sanitizeInput`: digits, one leading minus, the first
    /// point; a dollar figure typed in whole dollars (≥ 10,000) is read as
    /// dollars and converted to millions.
    static func sanitize(_ raw: String, unit: String) -> String {
        var result = ""
        var seenPoint = false
        for (index, character) in raw.enumerated() {
            if character.isNumber { result.append(character) }
            else if character == "-", index == 0 { result.append(character) }
            else if character == ".", !seenPoint { seenPoint = true; result.append(character) }
        }
        guard let number = Double(result) else { return "" }
        if unit == "#" { return String(Int(number.rounded())) }
        if unit == "$", abs(number) >= 10_000 { return display(number / 1_000_000) }
        return result
    }

    /// `stripTrailingZerosKeepDecimal`: `1.50` → `1.5`, `2` → `2.0`.
    static func display(_ number: Double) -> String {
        var text = String(format: "%.6f", number)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.append("0") }
        return text
    }

    /// `validateCellValue` for Revenue and EBITDA.
    static func validateStandard(_ raw: String, metric: String) -> CellError? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let number = Double(trimmed), number.isFinite else { return .invalidValue }
        if number == 0, metric != "ebitda" { return .invalidValue }
        if !range.contains(number) { return .outOfRange }
        return nil
    }

    /// `buildValidator(type, context)`. `revenue` is the same column's
    /// Revenue in millions, periodic context only.
    static func validate(_ raw: String, type: FinancialType, revenue: Double?, periodic: Bool) -> CellError? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let n = Double(trimmed), n.isFinite else { return .invalidValue }
        if type.isWholeNumber, n.rounded() != n { return .invalidValue }
        if let min = type.minAllowed, type.isMinInclusive ? n < min : n <= min { return .invalidValue }
        if let max = type.maxAllowed, n > max { return .invalidValue }
        if type.uom == "dollars", !range.contains(n) { return .outOfRange }
        if periodic, type.isRevenueConstrained, let revenue, revenue > 0, n > revenue { return .invalidValue }
        return nil
    }

    /// `buildInvalidValueMessage`.
    static func invalidMessage(for type: FinancialType, label: String, periodic: Bool) -> String {
        let minText = type.minAllowed.map { type.isMinInclusive ? "\(trim($0)) or greater" : "greater than \(trim($0))" }
        let pct = type.uom == "pct" ? "%" : ""
        if type.isWholeNumber {
            return minText.map { "\(label) must be a whole number \($0)." } ?? "\(label) must be a whole number."
        }
        if periodic, type.isRevenueConstrained {
            return type.minAllowed == nil
                ? "\(label) must be less than or equal to revenue."
                : "\(label) must be positive and less than or equal to revenue."
        }
        if let min = type.minAllowed, let max = type.maxAllowed {
            return type.isMinInclusive
                ? "\(label) must be between \(trim(min)) and \(trim(max))\(pct)."
                : "\(label) must be greater than \(trim(min)) and no more than \(trim(max))\(pct)."
        }
        if let minText { return "\(label) must be \(minText)." }
        if let max = type.maxAllowed { return "\(label) must be less than or equal to \(trim(max))." }
        return "\(label) must be a number."
    }

    static func message(for error: CellError, type: FinancialType?, label: String, periodic: Bool) -> String {
        switch error {
        case .outOfRange: "\(label): \(outOfRangeMessage)"
        case .invalidValue:
            type.map { invalidMessage(for: $0, label: label, periodic: periodic) } ?? "\(label) must be a number."
        }
    }

    private static func trim(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    /// Edited value → stored value: dollars are typed in millions.
    static func stored(_ raw: String, unit: String) -> Double? {
        guard let number = Double(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return unit == "$" ? number * 1_000_000 : number
    }

    /// Stored value → edited value.
    static func edited(_ value: Double, unit: String) -> String {
        unit == "$" ? display(value / 1_000_000) : (value.rounded() == value ? String(Int(value)) : String(value))
    }

    /// The summary table's money format: `$25.0M`, `$0`, `-`.
    static func summary(_ value: Double?, unit: String) -> String {
        guard let value else { return "-" }
        switch unit {
        case "%": return "\(edited(value, unit: "%"))%"
        case "#": return String(Int(value.rounded()))
        default:
            if value == 0 { return "$0" }
            return "$" + String(format: "%.1f", (value / 100_000).rounded() / 10) + "M"
        }
    }
}

// MARK: - KPIs and valuation

/// One "Current Metrics" row. Values validate on blur, and only valid,
/// blurred values are committed to the payload — the web's KPI store.
struct KPIRow: Equatable, Identifiable {
    var id: String
    var metric: String?
    var raw: String
    var error: CellError?
    /// The last blurred, valid text — what the payload sends. Typing never
    /// changes it, so nothing half-entered is autosaved.
    var committed: String?

    var isBlank: Bool { raw.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// "Valuation Expectation": base metric and a min/max multiple.
struct ValuationInput: Equatable {
    var metric: String?
    var min: Double?
    var max: Double?
    /// The last row that passed the commit rule. Web quirk, mirrored: an
    /// incomplete edit doesn't clear it — only Clear does.
    var committed: FinancialRow?

    static let maxMultiple: Double = 100
    static let sliderMax: Double = 20

    var hasInput: Bool { metric != nil || min != nil || max != nil }

    /// Commit when there's a metric and a max, and 0 ≤ min ≤ max ≤ 100.
    mutating func commitIfValid() {
        guard let metric, let max else { return }
        let lower = min ?? 0
        guard lower >= 0, max >= lower, max <= Self.maxMultiple else { return }
        committed = FinancialRow(financialType: metric, timePeriod: "na", isEstimated: false,
                                 minValue: lower, maxValue: max)
    }

    mutating func clear() {
        metric = nil; min = nil; max = nil; committed = nil
    }
}
