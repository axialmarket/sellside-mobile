//
//  DealDetailActions.swift
//  Axial Mobile
//

import Foundation

/// What the deal screen offers, and where. Mirrors
/// `SellSidebarService.createMenuOptions` (sell-sidebar.service.ts): footer
/// buttons and the ellipsis dropdown, both keyed on the row's
/// `supply_status`.
///
/// Two departures, both mobile's own:
/// - A pending NDA redline takes the primary slot, as it does on the card
///   (`DealResolveAction.offered`) — it's the thing the deal is waiting on.
/// - Report a Concern isn't offered; it needs the report modal, which mobile
///   doesn't have (see `DealRowAction`).
struct DealDetailActions: Equatable {
    enum Button: Hashable {
        case endDiscussions
        case sendFollowUp
        case pass
        case accept
        case sendCim
        case reviewRedlines
        /// The Update Status menu, as a footer button.
        case updateStatus
    }

    enum MenuItem: Hashable {
        case sendFollowUp
        case sendCim
        case sendMessage
        case addComment
        case updateStatus
        case copyEmail
        case copyPhone
    }

    /// Secondary first, primary last — the web's footer order.
    let footer: [Button]
    let menu: [MenuItem]

    static let teaserStatuses: Set<DealStatus> = [.sentTeaser, .targetExpired]
    static let preCimStatuses: Set<DealStatus> = [.targetPursued, .sentNda, .markedSentNda, .targetViewedNda,
                                                   .targetSignedNda, .markedNdaSigned]
    static let postCimStatuses: Set<DealStatus> = [.sentCim, .markedSentCim, .targetViewedCim, .markedReceivedIoi,
                                                    .markedExecutedLoi, .markedReceivedLoi, .markedClosed]
    static let endedStatuses: Set<DealStatus> = [.endedDiscussions, .targetEndedDiscussions]

    init(footer: [Button], menu: [MenuItem]) {
        self.footer = footer
        self.menu = menu
    }

    init(deal: SellsideDeal) {
        let status = deal.supplyStatus
        // `canSendCim`.
        let canSendCim = [.targetViewedNda, .targetSignedNda, .markedNdaSigned].contains(status)
        let contactItems: [MenuItem] = deal.isAnonymous ? [] : [.copyEmail, .copyPhone]

        if status == .targetRequestedAccess {
            footer = [.pass, .accept]
            menu = [.addComment]
        } else if Self.teaserStatuses.contains(status) {
            footer = [.endDiscussions, .sendFollowUp]
            menu = [.sendFollowUp, .addComment, .updateStatus]
        } else if Self.preCimStatuses.contains(status) || Self.postCimStatuses.contains(status) {
            let offersCim = canSendCim && Self.preCimStatuses.contains(status)
            let primary: Button = deal.showsNdaRedline ? .reviewRedlines : offersCim ? .sendCim : .updateStatus
            footer = [.endDiscussions, primary]
            menu = (offersCim ? [.sendCim] : []) + (deal.isInterested ? [.sendMessage] : [])
                + [.addComment, .updateStatus] + contactItems
        } else if Self.endedStatuses.contains(status) {
            footer = [.updateStatus]
            menu = []
        } else {
            // Recommended, declined, denied and the locked statuses: nothing
            // to do from here, which is the web's empty default too.
            footer = []
            menu = []
        }
    }

    /// The Messages tab — `messagesTabAvailable`: a contacted member (either
    /// list) who isn't still asking for access.
    static func showsMessages(for deal: SellsideDeal) -> Bool {
        deal.bucket != .recommended && deal.supplyStatus != .targetRequestedAccess
    }

    /// The reply box — `showMessageBox = contactedTargetRow?.isInterested`.
    static func canMessage(_ deal: SellsideDeal) -> Bool {
        deal.isInterested && showsMessages(for: deal)
    }
}

extension DealDetailActions.Button {
    func label(for deal: SellsideDeal) -> String {
        switch self {
        case .endDiscussions: "End Discussions"
        case .sendFollowUp: "Send Follow-Up"
        case .pass: DealResolveAction.pass.label(for: deal)
        case .accept: DealResolveAction.accept.label(for: deal)
        case .sendCim: DealResolveAction.shareCim.label(for: deal)
        case .reviewRedlines: DealResolveAction.reviewRedlines.label(for: deal)
        case .updateStatus: "Update Status"
        }
    }

    var systemImage: String {
        switch self {
        case .endDiscussions: "nosign"
        case .sendFollowUp: "arrowshape.turn.up.right"
        case .pass: DealResolveAction.pass.systemImage
        case .accept: DealResolveAction.accept.systemImage
        case .sendCim: DealResolveAction.shareCim.systemImage
        case .reviewRedlines: DealResolveAction.reviewRedlines.systemImage
        case .updateStatus: "arrow.triangle.2.circlepath"
        }
    }

    var isPrimary: Bool {
        switch self {
        case .endDiscussions, .pass: false
        default: true
        }
    }
}

/// The sidebar's tabs — `ESellSidebarTabs` — plus Files, which the web shows
/// in its deal details modal (`DealFilesComponent`) rather than the sidebar.
enum DealDetailTab: String, CaseIterable, Identifiable, Hashable {
    case profile
    case messages
    case files
    case comments

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .messages: "Messages"
        case .files: "Files"
        case .comments: "Comments"
        }
    }
}

/// Prev/next through the list the deal was opened from —
/// `SellSidebarActionsComponent.prevRow` / `nextRow`, which walk the grid's
/// row order and skip ids that have dropped out of it.
struct DealPager: Equatable, Hashable {
    let ids: [String]

    func previous(from id: String, among present: Set<String>) -> String? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        return ids[..<index].last(where: present.contains)
    }

    func next(from id: String, among present: Set<String>) -> String? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        return ids[ids.index(after: index)...].first(where: present.contains)
    }

    /// "3 of 12", or nil when the deal isn't in the list.
    func position(of id: String) -> String? {
        ids.firstIndex(of: id).map { "\($0 + 1) of \(ids.count)" }
    }
}

/// `POST /deals/nudge`.
struct FollowUpRequest: Encodable, Equatable {
    let dealPublicIds: [String]
    let message: String

    enum CodingKeys: String, CodingKey {
        case message
        case dealPublicIds = "deal_public_ids"
    }

    /// `FOLLOW_UP_DEFAULT_MESSAGE` (token-textarea.constants.ts) — not the
    /// project's automatic follow-up note, which words it differently.
    static let defaultMessage = "{recipient[first_name]},\n\nI'm following up on the recent deal I shared with you. If you are interested in learning more, please pursue the deal and I'll be in touch."
}
