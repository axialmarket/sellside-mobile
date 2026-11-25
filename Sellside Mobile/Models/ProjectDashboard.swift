//
//  ProjectDashboard.swift
//  Sellside Mobile
//

import Foundation

/// Everything the project detail screen needs resolved before it can render:
/// the project and its deals.
///
/// They're one value rather than two load states on purpose — the status
/// actions aren't safe to offer without the deals, since going under LOI or
/// closing asks which contacted party it was, and the tab bar's shape comes
/// out of them too. A half-loaded screen would shift under the user's thumb
/// and offer actions that dead-end.
struct ProjectDashboard: Equatable {
    let project: ProjectDetail
    let deals: [SellsideDeal]

    init(project: ProjectDetail, deals: [SellsideDeal] = []) {
        self.project = project
        self.deals = deals
    }

    // The three lists, partitioned by `SellsideDeal.bucket` — every deal
    // lands in exactly one of them.

    /// The deals in one section.
    ///
    /// Nothing is recommended while SmartShare is running: Axial is sharing
    /// the teaser automatically, so the web returns an empty recommended list
    /// too (`getFilteredRecommendedTargetsRows`). Every read goes through here
    /// so that rule can't be bypassed by reaching for `deals` directly.
    func deals(in bucket: SellsideDeal.Bucket) -> [SellsideDeal] {
        if bucket == .recommended, project.autoshareState == .enabled { return [] }
        return deals.filter { $0.bucket == bucket }
    }

    var recommendedDeals: [SellsideDeal] { deals(in: .recommended) }
    var contactedDeals: [SellsideDeal] { deals(in: .contacted) }
    var interestedDeals: [SellsideDeal] { deals(in: .interested) }

    /// Sections with something in them. Recommended drops out when empty —
    /// including under SmartShare — because there's nowhere to navigate to.
    var populatedSections: [SellsideDeal.Bucket] {
        SellsideDeal.Bucket.allCases.filter { bucket in
            bucket == .contacted || bucket == .interested || !deals(in: bucket).isEmpty
        }
    }

    /// Companies that can be named as the counterparty on an LOI or close.
    var counterpartyOptions: [CounterpartyOption] {
        CounterpartyOption.options(from: deals)
    }

    /// Swaps in a project returned by a mutation, keeping what we hold — the
    /// status endpoints answer with the intent alone.
    func replacingProject(_ project: ProjectDetail) -> ProjectDashboard {
        ProjectDashboard(project: project, deals: deals)
    }

    /// Folds a `deals/supply-marking-status` response into the deals we hold.
    /// Unmatched ids are ignored; the response can only ever answer for deals
    /// we asked about.
    func applying(_ updates: [DealStatusUpdate]) -> ProjectDashboard {
        guard !updates.isEmpty else { return self }
        let byId = Dictionary(updates.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return ProjectDashboard(
            project: project,
            deals: deals.map { deal in byId[deal.publicId].map(deal.applying) ?? deal }
        )
    }
}
