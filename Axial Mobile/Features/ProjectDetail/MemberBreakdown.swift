//
//  MemberBreakdown.swift
//  Axial Mobile
//

import Foundation

/// The dashboard's member breakdown chart: one member list, grouped into
/// buckets by one dimension.
///
/// Mirrors fe-app's member-breakdown (member-breakdown.consts.ts for the
/// buckets and their colours, member-breakdown.utils.ts for the grouping) and
/// `SellDashboardStore.memberBreakdown` for which lists are offered.
enum MemberBreakdown {
    /// What the bars are grouped by. `TGroupByDimension`.
    enum Dimension: String, CaseIterable, Identifiable {
        case companyType, capitalSource, closedDeals

        var id: String { rawValue }

        var label: String {
            switch self {
            case .companyType: "Company Type"
            case .capitalSource: "Capital Source"
            case .closedDeals: "Closed Deals"
            }
        }
    }

    /// One bar.
    struct Bar: Identifiable, Equatable {
        let label: String
        let count: Int
        let swatch: ChartSwatch

        var id: String { label }
    }

    // MARK: Lists

    /// The lists the chart can show. Recommended only when the project has
    /// one — which it doesn't under SmartShare, since nothing is recommended
    /// while Axial is sharing automatically.
    static func availableLists(in dashboard: ProjectDashboard) -> [SellsideDeal.Bucket] {
        SellsideDeal.Bucket.allCases.filter { $0 != .recommended || !dashboard.recommendedDeals.isEmpty }
    }

    /// The list shown before the seller picks one: Interested when it has
    /// more than one member, else Contacted when it does, else Recommended
    /// when there is one, else Interested.
    static func defaultList(in dashboard: ProjectDashboard) -> SellsideDeal.Bucket {
        if dashboard.interestedDeals.count > 1 { return .interested }
        if dashboard.contactedDeals.count > 1 { return .contacted }
        if !dashboard.recommendedDeals.isEmpty { return .recommended }
        return .interested
    }

    // MARK: Grouping

    /// Bars in display order, with empty buckets dropped — the chart only
    /// shows categories actually present in the list.
    static func bars(for deals: [SellsideDeal], by dimension: Dimension) -> [Bar] {
        let buckets = buckets(for: dimension)
        var counts: [String: Int] = [:]
        for deal in deals {
            counts[bucketLabel(for: deal, by: dimension), default: 0] += 1
        }
        return buckets.compactMap { bucket in
            guard let count = counts[bucket.label], count > 0 else { return nil }
            return Bar(label: bucket.label, count: count, swatch: bucket.swatch)
        }
    }

    // MARK: Drilling in

    /// The member-list filter that shows exactly one bar's members.
    ///
    /// Capital Source and Closed Deals filter on the bar's own label. Company
    /// Type filters on each member's type, so the Other bar opens with every
    /// type it gathered (Venture Capital, Unspecified, …) selected rather
    /// than a bucket the filter sheet doesn't know.
    static func filter(for bar: Bar, by dimension: Dimension, in deals: [SellsideDeal]) -> DealFilter {
        var filter = DealFilter()
        switch dimension {
        case .companyType:
            filter.companyTypes = Set(deals
                .filter { bucketLabel(for: $0, by: .companyType) == bar.label }
                .map(DealFilter.companyTypeKey))
        case .capitalSource:
            filter.capitalSources = [bar.label]
        case .closedDeals:
            filter.closedDeals = [bar.label]
        }
        return filter
    }

    private static let other = (label: "Other", swatch: ChartSwatch.chart10)

    /// `COMPANY_TYPE_BUCKETS`: account code, `ACCOUNT_TYPES` label, colour.
    /// Any code not listed falls into Other.
    static let companyTypes: [(code: String, label: String, swatch: ChartSwatch)] = [
        ("PE", "Private Equity Fund", .chart05),
        ("PF", "Independent Sponsor", .chart04),
        ("C", "Corporation", .chart03),
        ("HC", "Holding Company", .chart09),
        ("FO", "Family Office", .chart06),
        ("SF", "Search Fund", .chart01),
        ("II", "Individual Accredited Investor", .chart02),
        ("JC", "Junior/Mezz Lender", .chart07),
        ("SL", "Senior Lender", .chart12),
    ]

    /// `CAPITAL_SOURCE_BUCKETS`, short labels. Other also takes members with
    /// no capital source.
    static let capitalSources: [(source: CapitalSource, label: String, swatch: ChartSwatch)] = [
        (.committed, "Committed", .chart05),
        (.dealByDeal, "Deal by Deal", .chart04),
        (.balanceSheet, "Balance Sheet", .chart03),
        (.personalWealth, "Personal Wealth", .chart06),
    ]

    /// `CLOSED_DEAL_BUCKETS`: ranges, not one bar per count.
    static let closedDealRanges: [(label: String, range: ClosedRange<Int>, swatch: ChartSwatch)] = [
        ("None", Int.min...0, .chart01),
        ("1-2", 1...2, .chart07),
        ("3-4", 3...4, .chart02),
        ("5+", 5...Int.max, .chart09),
    ]

    private static func buckets(for dimension: Dimension) -> [(label: String, swatch: ChartSwatch)] {
        switch dimension {
        case .companyType: companyTypes.map { ($0.label, $0.swatch) } + [other]
        case .capitalSource: capitalSources.map { ($0.label, $0.swatch) } + [other]
        case .closedDeals: closedDealRanges.map { ($0.label, $0.swatch) }
        }
    }

    /// The bar a member falls into for one dimension.
    static func bucketLabel(for deal: SellsideDeal, by dimension: Dimension) -> String {
        switch dimension {
        case .companyType:
            companyTypes.first { $0.code == deal.companyCode }?.label ?? other.label
        case .capitalSource:
            capitalSources.first { $0.source == deal.capitalSource }?.label ?? other.label
        case .closedDeals:
            closedDealRanges.first { $0.range.contains(deal.closedDeals) }?.label ?? closedDealRanges[0].label
        }
    }
}

/// The web's categorical chart palette (`$component-charts-informative-chart-*`,
/// light theme), by token number. Colours live in `ChartPalette`; this stays
/// Foundation-only so the grouping above is testable without SwiftUI.
enum ChartSwatch: String, CaseIterable {
    case chart01, chart02, chart03, chart04, chart05, chart06
    case chart07, chart09, chart10, chart12
}
