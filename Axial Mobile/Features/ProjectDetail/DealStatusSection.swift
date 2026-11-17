//
//  DealStatusSection.swift
//  Axial Mobile
//

import Foundation

/// A member list grouped by status, as the web's member grids group their
/// rows (`gridStatusColumnDefinition`, `rowGroup: true`): one section per
/// status the cards show, in the funnel order the web groups by, each
/// keeping the list's own order inside it.
struct DealStatusSection: Identifiable {
    /// The web's `displayStatusKey` for every deal in the section.
    let key: String
    let title: String
    let deals: [SellsideDeal]

    var id: String { key }

    /// `deals` grouped by status. Sections follow `SUPPLY_STATUS_FUNNEL_ORDER`
    /// (deal.constants.ts) through the grid's `initialGroupOrderComparator`,
    /// which subtracts the two keys' positions in that list.
    ///
    /// A key the list doesn't name — Teaser Opened, Referral Received, and
    /// anything newer than the list — has position -1 there, so the web puts
    /// those groups first. Mirrored rather than fixed, so the two apps agree;
    /// among themselves they keep the order they first appear in.
    static func sections(for deals: [SellsideDeal]) -> [DealStatusSection] {
        var order: [String] = []
        var grouped: [String: [SellsideDeal]] = [:]
        for deal in deals {
            let key = deal.displayStatusKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(deal)
        }

        let ranked = order.enumerated().sorted { a, b in
            let lhs = rank(of: a.element), rhs = rank(of: b.element)
            return lhs != rhs ? lhs < rhs : a.offset < b.offset
        }
        return ranked.map { _, key in
            let members = grouped[key] ?? []
            return DealStatusSection(key: key, title: title(for: key, of: members[0]), deals: members)
        }
    }

    /// `SUPPLY_STATUS_FUNNEL_ORDER`, by raw value: the furthest along first,
    /// the ones that went nowhere last.
    static let funnelOrder = [
        "target_requested_access",
        "target_signed_nda",
        "marked_nda_signed",
        "nda_redlined",
        "marked_successfully_closed",
        "marked_executed_loi",
        "marked_received_loi",
        "marked_received_ioi",
        "sent_cim",
        "marked_sent_cim",
        "target_viewed_cim",
        "target_viewed_nda",
        "sent_nda",
        "marked_sent_nda",
        "target_pursued",
        "sent_teaser",
        "not_shared",
        "unmatched",
        "target_expired",
        "marked_target_declined",
        "target_declined",
        "passed",
        "ended_discussions",
        "archived",
        "recommended",
    ]

    /// Position in the funnel, or -1 for a key it doesn't list (`indexOf`).
    private static func rank(of key: String) -> Int {
        funnelOrder.firstIndex(of: key) ?? -1
    }

    private static func title(for key: String, of deal: SellsideDeal) -> String {
        key == SellsideDeal.ndaRedlinedKey ? "NDA Redlined" : deal.displayStatus.label
    }
}

extension SellsideDeal {
    /// The virtual status for an NDA redline waiting on the seller.
    /// `SUPPLY_STATUS.NDA_REDLINED`.
    static let ndaRedlinedKey = "nda_redlined"

    /// The status the web groups and filters this member by — `tableData.
    /// displayStatusKey` in supply-deals-row.model.ts. `displayStatus`, plus
    /// the redline, which the web checks after Teaser Opened and Referral
    /// Received and before folding the `marked_` statuses.
    var displayStatusKey: String {
        let status = displayStatus
        if status == .teaserOpened || status == .referralReceived { return status.rawValue }
        if showsNdaRedline { return Self.ndaRedlinedKey }
        return status.rawValue
    }
}
