//
//  CapitalRaiseForm.swift
//  Axial Mobile
//

import Foundation

/// The Capital Raise step (raise_capital only) — capital-raise.form.ts and
/// `extractCapitalRaiseFromForm`.
struct CapitalRaiseForm: Equatable {
    /// `type-capital`: a comma-joined, sorted list — `"debt,equity"`.
    var capitalType: String?
    /// Selected debt keys after roll-up (a fully checked parent is its key).
    var debtTypes: [String]
    var useOfFunds: [String]
    /// Entered in millions.
    var maxRange: Double?
    var minRange: Double?

    static let debtMax = 5

    init(intent: JSONValue) {
        let capital = intent[path: "terms.capital"]
        let types = capital?["capital_types"]?.strings.sorted() ?? []
        capitalType = types.isEmpty ? nil : types.joined(separator: ",")
        debtTypes = types.contains("debt") ? (capital?["debt_types"]?.strings ?? []) : []
        useOfFunds = capital?["use_of_funds"]?.strings ?? []
        maxRange = capital?[path: "financial_range.max_value"]?.number.map { $0 / 1_000_000 }
        minRange = capital?[path: "financial_range.min_value"]?.number.map { $0 / 1_000_000 }
    }

    var includesDebt: Bool { capitalType?.split(separator: ",").contains("debt") == true }

    mutating func setCapitalType(_ value: String?) {
        capitalType = value
        if !includesDebt { debtTypes = [] }
    }

    func write(into intent: inout JSONValue) {
        intent.set(.strings(useOfFunds), at: "terms.capital.use_of_funds")
        intent.set(.strings(capitalType.map { $0.split(separator: ",").map(String.init) } ?? []),
                   at: "terms.capital.capital_types")
        intent.set(.strings(debtTypes), at: "terms.capital.debt_types")
        intent.set(.number(orNull: minRange.map { $0 * 1_000_000 }), at: "terms.capital.financial_range.min_value")
        intent.set(.number(orNull: maxRange.map { $0 * 1_000_000 }), at: "terms.capital.financial_range.max_value")
    }

    enum Field {
        static let capitalType: SetupFieldKey = "capital.type-capital"
        static let debtTypes: SetupFieldKey = "capital.type-debt"
        static let useOfFunds: SetupFieldKey = "capital.selected_funds-use"
        static let maxRange: SetupFieldKey = "capital.max_range"
        static let minRange: SetupFieldKey = "capital.min_range"
    }

    func validate(into v: inout StepValidationBuilder) {
        v.require(Field.capitalType, satisfied: capitalType != nil, error: "")
        if includesDebt {
            v.require(Field.debtTypes, satisfied: !debtTypes.isEmpty, error: "")
        }
        v.require(Field.useOfFunds, satisfied: !useOfFunds.isEmpty, error: "")

        // `rangeMinMaxPairValidator` marks both; `min(0)` lets 0 through, so
        // "must be greater than 0" only fires for negatives (web quirk).
        let pairInvalid = minRange.flatMap { min in maxRange.map { min > $0 } } ?? false
        v.require(Field.maxRange, satisfied: maxRange.map { $0 >= 0 } == true && !pairInvalid,
                  error: maxRange.map { $0 < 0 } == true ? "Total amount must be greater than 0."
                      : pairInvalid ? "Total amount should be more than minimum check size." : "")
        v.require(Field.minRange, satisfied: minRange.map { $0 >= 0 } == true && !pairInvalid,
                  error: minRange.map { $0 < 0 } == true ? "Minimum check size must be greater than 0."
                      : pairInvalid ? "Minimum check size should be less than total amount." : "")
    }
}

enum CapitalOptions {
    static let capitalTypes: [SetupChoice<String>] = [
        .init(value: "equity", label: "Minority Equity"),
        .init(value: "debt", label: "Debt"),
        .init(value: "debt,equity", label: "Combination of equity and debt"),
        .init(value: "not_sure", label: "Open to any of the above"),
    ]

    static let useOfFunds: [SetupChoice<String>] = [
        .init(value: "growth", label: "Growth"),
        .init(value: "ma_financing", label: "Acquisition financing"),
        .init(value: "recapitalization", label: "Recapitalization"),
        .init(value: "turnaround", label: "Turnaround / distressed"),
        .init(value: "bs_strengthening", label: "Balance sheet strength"),
        .init(value: "other", label: "Other"),
    ]
}

/// `DEBT_HIERARCHY` with `NICE_DEBT_TYPES` labels. Parents expand; only
/// leaves are checkable; "Open to any type of debt" is exclusive.
enum DebtTypes {
    struct Node: Identifiable, Hashable {
        let key: String
        let label: String
        var children: [Node] = []
        var id: String { key }
        var leaves: [String] { children.isEmpty ? [key] : children.flatMap(\.leaves) }
    }

    static let openToAny = "not_sure"

    static let tree: [Node] = [
        Node(key: "senior", label: "Senior debt", children: [
            Node(key: "abl", label: "Asset-based lending", children: [
                Node(key: "accounts_receivable", label: "Accounts receivable financing"),
                Node(key: "factoring", label: "Factoring"),
                Node(key: "inventory", label: "Inventory financing"),
                Node(key: "equipment", label: "Equipment financing"),
            ]),
            Node(key: "senior_secured", label: "Secured debt"),
            Node(key: "senior_unsecured", label: "Unsecured debt"),
            Node(key: "cash_flow", label: "Cash-flow financing"),
            Node(key: "project_finance", label: "Project financing"),
            Node(key: "term_loan", label: "Term loans"),
            Node(key: "revolver", label: "Revolver loans"),
            Node(key: "small_business_administration", label: "Small Business Administration loans"),
        ]),
        Node(key: "junior", label: "Subordinated debt", children: [
            Node(key: "mezzanine", label: "Mezzanine debt"),
            Node(key: "junior_secured", label: "Secured debt"),
            Node(key: "junior_unsecured", label: "Unsecured debt"),
        ]),
        Node(key: "convertible", label: "Convertible debt"),
        Node(key: "unitranche", label: "Unitranche debt"),
        Node(key: "venture", label: "Venture debt"),
        Node(key: "other", label: "Other debt / loans"),
        Node(key: openToAny, label: "Open to any type of debt"),
    ]

    private static var allNodes: [Node] {
        func walk(_ nodes: [Node]) -> [Node] { nodes.flatMap { [$0] + walk($0.children) } }
        return walk(tree)
    }

    static func label(_ key: String) -> String { allNodes.first { $0.key == key }?.label ?? key }

    /// Hydration: parent keys back to their leaves.
    static func checkedLeaves(_ value: [String]) -> Set<String> {
        var leaves: Set<String> = []
        for key in value {
            if let node = allNodes.first(where: { $0.key == key }) { leaves.formUnion(node.leaves) }
            else { leaves.insert(key) }
        }
        return leaves
    }

    /// The value from checked leaves: fully checked parents roll up to their
    /// key. Parents are visited in index order (`abl` before `senior`), so
    /// once ABL has rolled up, Senior can never roll up — web quirk, kept.
    static func value(from leaves: Set<String>) -> [String] {
        var value = leafOrder.filter(leaves.contains)
        let parents = [tree[0].children[0], tree[0], tree[1]]
        var changed = true
        while changed {
            changed = false
            for parent in parents where !value.contains(parent.key) {
                let keys = parent.children.map(\.key)
                if !keys.isEmpty, keys.allSatisfy(value.contains) {
                    value.removeAll(where: keys.contains)
                    value.append(parent.key)
                    changed = true
                }
            }
        }
        return value
    }

    private static var leafOrder: [String] { tree.flatMap(\.leaves) }

    /// Toggling a leaf under the rules: the exclusive item clears the rest;
    /// anything else clears it; the cap blocks a sixth leaf.
    static func toggle(_ key: String, in leaves: Set<String>) -> Set<String> {
        var leaves = leaves
        if leaves.contains(key) {
            leaves.remove(key)
        } else if key == openToAny {
            leaves = [openToAny]
        } else {
            leaves.remove(openToAny)
            guard leaves.count < CapitalRaiseForm.debtMax else { return leaves }
            leaves.insert(key)
        }
        return leaves
    }
}
