//
//  DealAction.swift
//  Axial Mobile
//

import Foundation

/// An action offered on a single contacted member.
///
/// Mirrors `actionItems` in fe-app's contacted-members-grid.component.ts: the
/// same items, the same order, the same `when` filter. Kept whole even though
/// mobile can't run all of it yet — `isImplemented` is what the menu filters
/// on, so the parity list stays testable and the gap stays visible instead of
/// being quietly dropped.
enum DealAction: String, CaseIterable, Identifiable {
    case sendFollowUp
    case updateStatus
    case endDiscussions
    case addInternalComment
    case reportConcern

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sendFollowUp: "Send Follow-Up"
        case .updateStatus: "Update Status"
        case .endDiscussions: "End Discussions"
        case .addInternalComment: "Add Internal Comment"
        case .reportConcern: "Report a Concern"
        }
    }

    var systemImage: String {
        switch self {
        case .sendFollowUp: "arrowshape.turn.up.left"
        case .updateStatus: "arrow.triangle.2.circlepath"
        case .endDiscussions: "nosign"
        case .addInternalComment: "bubble.left"
        case .reportConcern: "flag"
        }
    }

    /// Whether mobile can carry the action out yet. Follow-ups need a message
    /// composer, comments need the deal notes drawer, and concerns need the
    /// report modal — none of which exist here. Status changes do.
    var isImplemented: Bool {
        switch self {
        case .updateStatus, .endDiscussions: true
        case .sendFollowUp, .addInternalComment, .reportConcern: false
        }
    }

    /// Web's `canFollowUp` (sell.helpers.ts) is the only per-deal predicate;
    /// everything else is offered unconditionally.
    func isAvailable(for deal: SellsideDeal) -> Bool {
        switch self {
        case .sendFollowUp:
            deal.supplyStatus == .sentTeaser || deal.supplyStatus == .targetExpired
        default:
            true
        }
    }

    /// The web's action list for a deal, in web order.
    static func available(for deal: SellsideDeal) -> [DealAction] {
        allCases.filter { $0.isAvailable(for: deal) }
    }

    /// What the menu actually renders today.
    ///
    /// Nothing on a recommended deal: these are the *contacted* grid's
    /// actions, and marking an NDA sent on a member you've never shared with
    /// is nonsense. Web's recommended grid has its own set — share teaser,
    /// ignore, pin — which mobile doesn't have yet.
    static func offered(for deal: SellsideDeal) -> [DealAction] {
        guard deal.bucket != .recommended else { return [] }
        return available(for: deal).filter(\.isImplemented)
    }
}

/// A status a deal can be marked as from the Update Status submenu.
///
/// Mirrors `SUPPLY_STATUS_FUNNEL` (sellside-deals.constants.ts) for the list
/// and order, and the `USER_ACTIONS` → status mapping in
/// sell-actions.service.ts for what each one posts.
enum DealStatusUpdateOption: String, CaseIterable, Identifiable {
    case ndaSent
    case ndaSigned
    case cimSent
    case ioiReceived
    case loiReceived
    case loiExecuted
    case memberDeclined
    case successfullyClosed

    var id: String { rawValue }

    var label: String { status.label }

    /// The status posted to `deals/supply-marking-status`.
    var status: DealStatus {
        switch self {
        case .ndaSent: .markedSentNda
        case .ndaSigned: .markedNdaSigned
        case .cimSent: .markedSentCim
        case .ioiReceived: .markedReceivedIoi
        case .loiReceived: .markedReceivedLoi
        case .loiExecuted: .markedExecutedLoi
        case .memberDeclined: .markedTargetDeclined
        case .successfullyClosed: .markedClosed
        }
    }

    /// Web drops a separator after `mark_cim_sent` and `mark_loi_executed`;
    /// those become `Section` breaks in the menu.
    static let groups: [[DealStatusUpdateOption]] = [
        [.ndaSent, .ndaSigned, .cimSent],
        [.ioiReceived, .loiReceived, .loiExecuted],
        [.memberDeclined, .successfullyClosed],
    ]
}

/// A deal action resolved down to what the list has to carry out. The two
/// status cases end up at `deals/supply-marking-status` (separate because
/// ending discussions is destructive and gets confirmed first); `resolve`
/// is a card's own call to action — accept, pass, redlines, CIM.
enum DealActionRequest: Equatable {
    case updateStatus(DealStatusUpdateOption)
    case endDiscussions
    case resolve(DealResolveAction)

    /// The status a marking posts; nil for a resolve, which has its own call.
    var status: DealStatus? {
        switch self {
        case .updateStatus(let option): option.status
        case .endDiscussions: .endedDiscussions
        case .resolve: nil
        }
    }
}
