//
//  DealAction.swift
//  Sellside Mobile
//

import Foundation

/// What one member's row offers — the web grids' `actionItems`
/// (recommended-, contacted- and interested-members-grid.component.ts): a
/// full menu behind the ellipsis, and the one or two `quickButtonOrder`
/// items the web shows on hover. On a phone the quick ones are the swipe
/// actions and the full menu is the context menu and the More sheet, all
/// from here so they can't drift.
///
/// Only what mobile can carry out is listed. Left on the web: Draft
/// Outreach Note and Send Message (compose flows of their own), Pin to Top /
/// Unpin (mobile doesn't hold the pin flag), Copy Email / Phone (not on the
/// list's payload), Add Internal Comment and Report a Concern (the deal
/// screen has comments; the report modal isn't built).
enum DealRowAction: Hashable, Identifiable {
    case accept
    case pass
    /// Mobile's own: a pending redline is what the deal is waiting on, as on
    /// the deal screen's footer (`DealResolveAction.offered`).
    case reviewRedlines
    case shareCim
    case updateStatus
    case endDiscussions
    case restartDiscussions

    var id: Self { self }

    /// The full menu, in the web's order.
    static func menu(for deal: SellsideDeal) -> [DealRowAction] {
        // Recommended grid: Pass on Member (after Draft Outreach Note).
        if deal.bucket == .recommended { return [.pass] }
        // Interested grid, for an access request: Accept, then Pass.
        if deal.supplyStatus == .targetRequestedAccess { return [.accept, .pass] }
        var actions: [DealRowAction] = deal.showsNdaRedline ? [.reviewRedlines] : []
        // Share CIM is on the interested grid only.
        if deal.isInterested { actions.append(.shareCim) }
        actions.append(.updateStatus)
        actions.append(deal.supplyStatus == .endedDiscussions ? .restartDiscussions : .endDiscussions)
        return actions
    }

    /// The swipe actions: the web's `quickButtonOrder` items mobile can run,
    /// at most two, led by a waiting redline.
    static func quick(for deal: SellsideDeal) -> [DealRowAction] {
        let base: [DealRowAction]
        if deal.bucket == .recommended {
            base = [.pass]
        } else if deal.supplyStatus == .targetRequestedAccess {
            base = [.accept, .pass]
        } else if deal.isInterested,
                  deal.supplyStatus == .targetSignedNda || deal.supplyStatus == .markedNdaSigned {
            // Share CIM, then Send Message, which mobile doesn't have.
            base = [.shareCim]
        } else {
            // Send Message (interested) is web-only; Update Status follows.
            base = [.updateStatus]
        }
        return Array(((deal.showsNdaRedline ? [.reviewRedlines] : []) + base).prefix(2))
    }

    /// Swiping right, from the leading edge: Pass, for a member waiting on
    /// your approval, so passing and accepting sit on opposite sides and
    /// can't be hit by the same swipe.
    static func leadingSwipe(for deal: SellsideDeal) -> [DealRowAction] {
        deal.supplyStatus == .targetRequestedAccess ? [.pass] : []
    }

    /// Swiping left, from the trailing edge: the rest of the quick actions —
    /// Accept for an access request, Send CIM once the NDA is signed, a
    /// waiting redline — followed by More.
    static func trailingSwipe(for deal: SellsideDeal) -> [DealRowAction] {
        let leading = leadingSwipe(for: deal)
        return quick(for: deal).filter { !leading.contains($0) }
    }

    func label(for deal: SellsideDeal) -> String {
        switch self {
        case .accept: DealResolveAction.accept.label(for: deal)
        case .pass: "Pass on Member"
        case .reviewRedlines: "Review Redlines"
        case .shareCim: "Send CIM"
        case .updateStatus: "Update Status"
        case .endDiscussions: "End Discussions"
        case .restartDiscussions: "Restart Discussions"
        }
    }

    /// The swipe button's shorter label.
    var shortLabel: String {
        switch self {
        case .accept: "Accept"
        case .pass: "Pass"
        case .reviewRedlines: "Redlines"
        case .shareCim: "Send CIM"
        case .updateStatus: "Status"
        case .endDiscussions: "End"
        case .restartDiscussions: "Restart"
        }
    }

    var systemImage: String {
        switch self {
        case .accept: "checkmark"
        case .pass: "xmark"
        case .reviewRedlines: "doc.text.magnifyingglass"
        case .shareCim: "paperplane"
        case .updateStatus: "arrow.triangle.2.circlepath"
        case .endDiscussions: "nosign"
        case .restartDiscussions: "arrow.counterclockwise"
        }
    }

    /// Red in menus: these end something with the buyer.
    var isDestructive: Bool {
        self == .endDiscussions || self == .pass
    }

    /// What the list carries out. Nil for Update Status, which is a submenu.
    var request: DealActionRequest? {
        switch self {
        case .accept: .resolve(.accept)
        case .pass: .resolve(.pass)
        case .reviewRedlines: .resolve(.reviewRedlines)
        case .shareCim: .resolve(.shareCim)
        case .updateStatus: nil
        case .endDiscussions: .endDiscussions
        case .restartDiscussions: .restartDiscussions
        }
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

    /// Whether the member already shows this status. A marked status shows
    /// as its automatic twin ("NDA Sent" either way), so it's the label that
    /// decides, as it is on the card.
    func isCurrent(for deal: SellsideDeal) -> Bool {
        label == deal.displayStatus.label
    }

    /// SF Symbols, so the deal menus read like the project status menu.
    var systemImage: String {
        switch self {
        case .ndaSent: "doc.text"
        case .ndaSigned: "signature"
        case .cimSent: "doc.richtext"
        case .ioiReceived: "envelope.open"
        case .loiReceived: "tray.and.arrow.down"
        case .loiExecuted: "checkmark.seal"
        case .memberDeclined: "hand.raised"
        case .successfullyClosed: "trophy"
        }
    }

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

/// A row action resolved down to what the list has to carry out. The two
/// status cases end up at the status endpoints (separate because ending
/// discussions gets confirmed first); `restartDiscussions` has its own;
/// `resolve` is a card's own call to action — accept, pass, redlines, CIM.
enum DealActionRequest: Equatable {
    case updateStatus(DealStatusUpdateOption)
    case endDiscussions
    case restartDiscussions
    case resolve(DealResolveAction)
    /// Open the deal on a tab — the actions sheet's View rows.
    case open(DealDetailTab)
    /// Open the deal with a compose sheet up — message, follow-up, comment.
    case compose(DealCompose)

    /// The status a marking posts; nil for a resolve, which has its own call.
    var status: DealStatus? {
        switch self {
        case .updateStatus(let option): option.status
        case .endDiscussions: .endedDiscussions
        case .restartDiscussions, .resolve, .open, .compose: nil
        }
    }
}

/// What a deal screen can open with a sheet already up. Each is the deal
/// screen's own composer (`DealDetailView.Sheet`). No follow-up: the web has
/// none per deal; it's a project setting sent automatically.
enum DealCompose: String, Hashable {
    case message
    case comment

    /// The tab it belongs with, so closing the composer lands on the thread
    /// it added to.
    var tab: DealDetailTab {
        switch self {
        case .message: .messages
        case .comment: .comments
        }
    }
}

/// The actions sheet's layout, Mail's More: up to four tiles across the top
/// — moving forward first, the destructive one last and red — then rows in
/// three groups: the deal's status, talking to the member, and the deal's
/// own pages.
struct DealActionsLayout: Equatable {
    enum Item: Hashable, Identifiable {
        case action(DealRowAction)
        case compose(DealCompose)
        case view(DealDetailTab)

        var id: Self { self }
    }

    let tiles: [Item]
    let sections: [[Item]]

    init(deal: SellsideDeal) {
        let menu = DealRowAction.menu(for: deal)
        let quick = DealRowAction.quick(for: deal)

        // Talking to them: Send Message once they're interested and past an
        // access request (the interested grid's own condition), and an
        // internal comment, which every grid offers.
        var compose: [DealCompose] = []
        if DealDetailActions.canMessage(deal) { compose.append(.message) }
        compose.append(.comment)

        let forward = quick.filter { !$0.isDestructive }.map(Item.action)
        let talk = compose.first.map { [Item.compose($0)] } ?? []
        let destructive = menu.first(where: \.isDestructive).map { [Item.action($0)] } ?? []
        let tiles = Array((forward + talk).prefix(4 - destructive.count)) + destructive
        self.tiles = tiles

        let status = menu.map(Item.action).filter { !tiles.contains($0) }
        let talking = compose.map(Item.compose).filter { !tiles.contains($0) }
        let pages = DealDetailTab.allCases
            .filter { $0 != .messages || DealDetailActions.showsMessages(for: deal) }
            .map(Item.view)
        sections = [status, talking, pages].filter { !$0.isEmpty }
    }
}
