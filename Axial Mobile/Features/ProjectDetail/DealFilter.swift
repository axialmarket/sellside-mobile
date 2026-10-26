//
//  DealFilter.swift
//  Axial Mobile
//

import Foundation

/// The filters on a member list. Mirrors the most-used column filters on the
/// web's member grids (contacted/interested/recommended-members-grid
/// .component.ts), scaled to what the card shows:
///
/// - **Status** — set filter on `displayStatusKey`, the status the card shows.
/// - **Company Type** — set filter on `ACCOUNT_TYPES[companyCode]`.
/// - **Capital Source** — set filter, folded into the breakdown chart's
///   buckets so the two read alike.
/// - **Has new messages** — the web's Last Message column filters on
///   "has a message" (Yes/No). Unread is what matters on a phone.
///
/// Values within one filter OR together and separate filters AND, as in
/// ag-grid. An empty set means "no filter", not "match nothing".
struct DealFilter: Equatable {
    var statuses: Set<DealStatus> = []
    var companyTypes: Set<String> = []
    var capitalSources: Set<String> = []
    var hasNewMessages = false

    /// Stands for a member with no company type — the web's "(Blanks)".
    static let unspecifiedCompanyType = "Unspecified"

    /// One per category in use; drives the toolbar button.
    var activeCount: Int {
        [!statuses.isEmpty, !companyTypes.isEmpty, !capitalSources.isEmpty, hasNewMessages]
            .filter { $0 }.count
    }

    var isActive: Bool { activeCount > 0 }

    func matches(_ deal: SellsideDeal) -> Bool {
        if !statuses.isEmpty, !statuses.contains(deal.displayStatus) { return false }
        if !companyTypes.isEmpty, !companyTypes.contains(Self.companyTypeKey(for: deal)) { return false }
        if !capitalSources.isEmpty, !capitalSources.contains(Self.capitalSourceKey(for: deal)) { return false }
        if hasNewMessages, deal.unreadMessageCount == 0 { return false }
        return true
    }

    static func companyTypeKey(for deal: SellsideDeal) -> String {
        deal.companyType ?? unspecifiedCompanyType
    }

    /// No capital source reads as Other, as on the breakdown chart.
    static func capitalSourceKey(for deal: SellsideDeal) -> String {
        (deal.capitalSource ?? .other).label
    }
}

// MARK: - Search, filter, sort

extension DealFilter {
    /// The list's header: "24 members", or "6 of 24 members" once a search
    /// or filter is hiding some.
    static func countSummary(shown: Int, total: Int) -> String {
        let noun = total == 1 ? "member" : "members"
        return shown == total ? "\(total) \(noun)" : "\(shown) of \(total) \(noun)"
    }

    /// What a member list shows: searched, filtered, newest activity first.
    func apply(to deals: [SellsideDeal], query: String) -> [SellsideDeal] {
        Self.sorted(Self.matching(query, in: deals).filter(matches))
    }

    /// Company (and the account it acts for), member, company type, location
    /// and last message, case- and diacritic-insensitive. A blank query
    /// matches everything. The web's quick filter covers the same ground
    /// (`constructCompanySearchText` and each column's `getQuickFilterText`).
    static func matching(_ query: String, in deals: [SellsideDeal]) -> [SellsideDeal] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deals }
        return deals.filter { deal in
            [deal.displayName, deal.demandAccountName, deal.demandUserName, deal.companyType,
             deal.location, deal.lastMessage]
                .compactMap { $0 }
                .contains { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Most recently updated first — the web grids' leading column is Last
    /// Updated. Undated members go last, then by name so the order is stable.
    static func sorted(_ deals: [SellsideDeal]) -> [SellsideDeal] {
        deals.sorted { a, b in
            switch (a.statusDate, b.statusDate) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs > rhs
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
    }
}

// MARK: - Options

/// What the member filter sheet can offer, derived from one list's members.
/// Anything already selected stays listed at a count of zero, so a filter
/// can't be left on with no way to see it.
struct DealFilterOptions: Equatable {
    let statuses: [FilterOption<DealStatus>]
    let companyTypes: [FilterOption<String>]
    let capitalSources: [FilterOption<String>]

    init(deals: [SellsideDeal], selected filter: DealFilter = DealFilter()) {
        let byStatus = Dictionary(grouping: deals, by: \.displayStatus).mapValues(\.count)
        statuses = Self.statusOrder
            .filter { byStatus[$0] != nil || filter.statuses.contains($0) }
            .map { FilterOption(value: $0, label: $0.label, count: byStatus[$0] ?? 0) }

        let byType = Dictionary(grouping: deals, by: DealFilter.companyTypeKey).mapValues(\.count)
        companyTypes = Set(byType.keys).union(filter.companyTypes)
            .map { FilterOption(value: $0, label: $0, count: byType[$0] ?? 0) }
            .sorted { a, b in
                // The blank bucket last rather than alphabetised.
                if (a.value == DealFilter.unspecifiedCompanyType) != (b.value == DealFilter.unspecifiedCompanyType) {
                    return b.value == DealFilter.unspecifiedCompanyType
                }
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }

        let bySource = Dictionary(grouping: deals, by: DealFilter.capitalSourceKey).mapValues(\.count)
        capitalSources = (MemberBreakdown.capitalSources.map(\.label) + ["Other"])
            .filter { bySource[$0] != nil || filter.capitalSources.contains($0) }
            .map { FilterOption(value: $0, label: $0, count: bySource[$0] ?? 0) }
    }

    /// Funnel order, with the two display-only statuses beside the ones
    /// they're derived from rather than at the end where the enum keeps them.
    static let statusOrder: [DealStatus] = DealStatus.allCases.flatMap { status -> [DealStatus] in
        switch status {
        case .teaserOpened, .referralReceived, .unknown: []
        case .sentTeaser: [.sentTeaser, .teaserOpened]
        case .targetRequestedAccess: [.targetRequestedAccess, .referralReceived]
        default: [status]
        }
    } + [.unknown]
}
