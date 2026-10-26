//
//  ProjectFilter.swift
//  Axial Mobile
//

import Foundation

/// The filters on the projects list. Mirrors the column filters on fe-app
/// `MarketDealsGridComponent` (market-deals-grid.component.ts), scaled down
/// to what the card actually shows:
///
/// - **Status** and **Contact** are ag-grid set filters on the web; same here.
/// - **Industries** is a free-text filter on the web, over
///   `formatSectors()` ("vertical + activity"). Mobile offers the sector
///   *names* the card prints as a set instead — the search field already
///   covers free text over sectors.
/// - **Created** is an `agDateColumnFilter` (before / after / range). Mobile
///   offers a few trailing windows instead of a date-range editor.
/// - **Recommended / Contacted / Interested** are number filters on the web.
///   Mobile reduces each to "has any", plus "has new recommendations" since
///   the card calls those out.
/// - **Project Type** isn't on the card, so it isn't offered.
///
/// Combination follows ag-grid: values within one filter OR together,
/// separate filters AND. An empty set means "no filter", not "match nothing".
struct ProjectFilter: Equatable {
    var statuses: Set<SupplyState> = []
    /// Assigned contacts by full name — the web's set-filter key
    /// (`assignedToUserFullName`). `ProjectFilter.unassigned` stands for
    /// projects with nobody assigned.
    var contacts: Set<String> = []
    var sectors: Set<String> = []
    var created: CreatedWindow?
    var activity: Set<Activity> = []

    /// Contact key for a project with no assignee; the web's "(Blanks)".
    static let unassigned = ""

    enum CreatedWindow: String, CaseIterable, Identifiable {
        case pastWeek, pastMonth, pastQuarter, pastYear

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pastWeek: "Past Week"
            case .pastMonth: "Past Month"
            case .pastQuarter: "Past 3 Months"
            case .pastYear: "Past Year"
            }
        }

        /// The earliest creation date inside the window.
        func start(before now: Date, calendar: Calendar = .current) -> Date {
            let (component, value): (Calendar.Component, Int) = switch self {
            case .pastWeek: (.day, -7)
            case .pastMonth: (.month, -1)
            case .pastQuarter: (.month, -3)
            case .pastYear: (.year, -1)
            }
            return calendar.date(byAdding: component, value: value, to: now) ?? now
        }
    }

    enum Activity: String, CaseIterable, Identifiable {
        case newRecommendations, contacted, interested

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newRecommendations: "Has New Recommendations"
            case .contacted: "Has Contacted Members"
            case .interested: "Has Interested Members"
            }
        }

        func matches(_ project: SellsideProject) -> Bool {
            switch self {
            case .newRecommendations: (project.unreadRecommendations ?? 0) > 0
            case .contacted: project.activeDeals > 0
            case .interested: project.interestedMembers > 0
            }
        }
    }

    var isActive: Bool { activeCount > 0 }

    /// How many filters are narrowing the list — one per category in use,
    /// the way the web marks one icon per filtered column. Drives the badge.
    var activeCount: Int {
        [!statuses.isEmpty, !contacts.isEmpty, !sectors.isEmpty,
         created != nil, !activity.isEmpty].filter { $0 }.count
    }

    func matches(_ project: SellsideProject, now: Date = .now) -> Bool {
        if !statuses.isEmpty, !statuses.contains(project.supplyState) { return false }
        if !contacts.isEmpty, !contacts.contains(Self.contactKey(for: project)) { return false }
        if !sectors.isEmpty, !project.sectors.contains(where: { sectors.contains($0.name) }) {
            return false
        }
        if let created {
            // A project with no creation date can't be inside a window — the
            // web's date filter drops blanks the same way.
            guard let createdAt = project.createdAt,
                  createdAt >= created.start(before: now) else { return false }
        }
        return activity.allSatisfy { $0.matches(project) }
    }

    func apply(to projects: [SellsideProject], now: Date = .now) -> [SellsideProject] {
        guard isActive else { return projects }
        return projects.filter { matches($0, now: now) }
    }

    static func contactKey(for project: SellsideProject) -> String {
        project.assignedToUser?.fullName.trimmingCharacters(in: .whitespaces) ?? unassigned
    }
}

/// What the filter sheet can offer, derived from the projects we hold.
/// Counts are over the whole list rather than cross-filtered, so a row's
/// number doesn't change under the user's thumb as they tick others.
struct ProjectFilterOptions: Equatable {
    typealias Option = FilterOption

    let statuses: [Option<SupplyState>]
    let contacts: [Option<String>]
    let sectors: [Option<String>]

    /// Anything already selected stays listed even after a refresh drops the
    /// last project carrying it, at a count of zero — otherwise it would be
    /// a filter the user can't see to turn off.
    init(projects: [SellsideProject], selected filter: ProjectFilter = ProjectFilter()) {
        let byStatus = Dictionary(grouping: projects, by: \.supplyState).mapValues(\.count)
        statuses = SupplyState.sectionOrder
            .filter { byStatus[$0] != nil || filter.statuses.contains($0) }
            .map { Option(value: $0, label: $0.label, count: byStatus[$0] ?? 0) }

        let byContact = Dictionary(grouping: projects, by: ProjectFilter.contactKey).mapValues(\.count)
        contacts = Self.sortedOptions(byContact, including: filter.contacts) {
            $0 == ProjectFilter.unassigned ? "Unassigned" : $0
        }

        var bySector: [String: Int] = [:]
        for project in projects {
            // A project listing a sector twice still counts once.
            for name in Set(project.sectors.map(\.name)) { bySector[name, default: 0] += 1 }
        }
        sectors = Self.sortedOptions(bySector, including: filter.sectors) { $0 }
    }

    /// The value shown beside a pushed list's row in the sheet.
    static func summary(of selection: Set<String>, in options: [Option<String>]) -> String {
        FilterOption.summary(of: selection, in: options)
    }

    /// Alphabetical, with the unassigned bucket last rather than sorted as "".
    private static func sortedOptions(
        _ counts: [String: Int], including selected: Set<String>, label: (String) -> String
    ) -> [Option<String>] {
        Set(counts.keys).union(selected)
            .map { Option(value: $0, label: label($0), count: counts[$0] ?? 0) }
            .sorted { a, b in
                if (a.value == ProjectFilter.unassigned) != (b.value == ProjectFilter.unassigned) {
                    return b.value == ProjectFilter.unassigned
                }
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }
    }
}
