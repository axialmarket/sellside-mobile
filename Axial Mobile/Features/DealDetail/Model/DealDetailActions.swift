//
//  DealDetailActions.swift
//  Axial Mobile
//

import Foundation

/// What the deal screen offers, and where. Mirrors
/// `SellSidebarService.createMenuOptions` (sell-sidebar.service.ts): footer
/// buttons and the ellipsis dropdown, keyed on the row's `supply_status`
/// alone — the web's sidebar never asks which list it was opened from.
///
/// Left on the web, so missing here: Draft Outreach Note (a recommendation's
/// primary button), the Pre-Approve / Require Approval toggle, and Report a
/// Concern. There is no per-deal follow-up on the web at all — follow-up is
/// a project setting (Project Setup › Outreach › Follow-Up Note) sent
/// automatically — so there's none here either.
struct DealDetailActions: Equatable {
    enum Button: Hashable {
        case endDiscussions
        case restartDiscussions
        case pass
        case accept
        case sendCim
        case reviewRedlines
        /// The Update Status menu, as a footer button.
        case updateStatus
    }

    enum MenuItem: Hashable {
        case sendCim
        case sendMessage
        case reviewRedlines
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

    init(footer: [Button], menu: [MenuItem]) {
        self.footer = footer
        self.menu = menu
    }

    /// The web's branches, first match wins (svc:123-537).
    init(deal: SellsideDeal) {
        let status = deal.supplyStatus
        let contactItems: [MenuItem] = deal.isAnonymous ? [] : [.copyEmail, .copyPhone]
        let message: [MenuItem] = deal.isInterested ? [.sendMessage] : []

        if status == .notShared {
            // A recommendation: Pass on Member, then Draft Outreach Note,
            // which stays on the web. The menu is only Report a Concern.
            footer = [.pass]
            menu = []
        } else if Self.teaserStatuses.contains(status) {
            footer = [.endDiscussions]
            menu = [.addComment, .updateStatus]
        } else if status == .targetRequestedAccess {
            footer = [.pass, .accept]
            menu = [.addComment]
        } else if deal.showsNdaRedline {
            // Ahead of every later branch, ended discussions included, and
            // with no End Discussions anywhere.
            footer = [.updateStatus, .reviewRedlines]
            menu = message + [.reviewRedlines, .addComment, .updateStatus] + contactItems
        } else if Self.preCimStatuses.contains(status) {
            // `canSendCim`.
            let canSendCim = [.targetViewedNda, .targetSignedNda, .markedNdaSigned].contains(status)
            footer = [.endDiscussions, canSendCim ? .sendCim : .updateStatus]
            menu = (canSendCim ? [.sendCim] : []) + message + [.addComment, .updateStatus] + contactItems
        } else if Self.postCimStatuses.contains(status) {
            footer = [.endDiscussions, .updateStatus]
            menu = message + [.addComment, .updateStatus] + contactItems
        } else if status == .endedDiscussions {
            // Only `ended_discussions`: a member who ended it themselves
            // falls through to nothing, as on the web.
            footer = [.updateStatus, .restartDiscussions]
            menu = []
        } else {
            // Declined, passed, the locked statuses and anything unknown:
            // the web returns nothing, so no footer and a disabled menu.
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
        case .restartDiscussions: "Restart Discussions"
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
        case .restartDiscussions: "arrow.counterclockwise"
        case .pass: DealResolveAction.pass.systemImage
        case .accept: DealResolveAction.accept.systemImage
        case .sendCim: DealResolveAction.shareCim.systemImage
        case .reviewRedlines: DealResolveAction.reviewRedlines.systemImage
        case .updateStatus: "arrow.triangle.2.circlepath"
        }
    }

    /// The web's: Update Status is always secondary, so a footer of End
    /// Discussions and Update Status has no primary, as on the web.
    var isPrimary: Bool {
        switch self {
        case .endDiscussions, .pass, .updateStatus: false
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
        case .profile: "Company Profile"
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
