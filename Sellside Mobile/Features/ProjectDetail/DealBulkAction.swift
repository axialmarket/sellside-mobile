//
//  DealBulkAction.swift
//  Sellside Mobile
//

import Foundation

/// What a member list can do to everyone selected — the web grids'
/// `bulkActions` (recommended-, contacted- and interested-members-
/// grid.component.ts), worked out from the selection itself so a dashboard
/// drill-down gets the same rules as the list it narrows.
///
/// Left on the web for now: Draft Outreach Note and Send Message (each a
/// compose flow of its own), Pin to Top / Unpin (mobile doesn't hold the pin
/// flag), and the pre-approval toggles (only offered when the web's grid is
/// grouped by approval).
enum DealBulkAction: Hashable, Identifiable {
    case accept
    case pass
    case shareCim
    case updateStatus
    case endDiscussions
    case restartDiscussions

    var id: Self { self }

    /// Offered for a selection, in the web's order.
    static func offered(for selected: [SellsideDeal]) -> [DealBulkAction] {
        guard !selected.isEmpty else { return [] }
        // Recommended: Pass on Member is the one bulk action mobile carries.
        if selected.allSatisfy({ $0.bucket == .recommended }) { return [.pass] }
        if selected.contains(where: { $0.bucket == .recommended }) { return [] }
        // Everyone is asking for access: Accept and Pass, and nothing else.
        if selected.allSatisfy({ $0.supplyStatus == .targetRequestedAccess }) { return [.accept, .pass] }

        var actions: [DealBulkAction] = []
        // Interested grid: offered when at least one has pursued; the note
        // sheet leaves out anyone who isn't eligible.
        if selected.contains(where: { $0.isInterested && $0.hasTargetPursued }) { actions.append(.shareCim) }
        actions.append(.updateStatus)
        let anyEnded = selected.contains { $0.supplyStatus == .endedDiscussions }
        actions.append(anyEnded ? .restartDiscussions : .endDiscussions)
        return actions
    }

    func label(for selected: [SellsideDeal]) -> String {
        switch self {
        case .accept: BulkAcceptCopy(deals: selected).title
        case .pass: "Pass"
        case .shareCim: "Send CIM"
        case .updateStatus: "Update Status"
        case .endDiscussions: "End Discussions"
        case .restartDiscussions: "Restart Discussions"
        }
    }

    var systemImage: String {
        switch self {
        case .accept: "checkmark"
        case .pass: "xmark"
        case .shareCim: "paperplane"
        case .updateStatus: "arrow.triangle.2.circlepath"
        case .endDiscussions: "nosign"
        case .restartDiscussions: "arrow.counterclockwise"
        }
    }

    /// The web's bulk Update Status menu: the single-row options, less
    /// Executed LOI and Successfully Closed.
    static let statusGroups: [[DealStatusUpdateOption]] = DealStatusUpdateOption.groups
        .map { $0.filter { $0 != .loiExecuted && $0 != .successfullyClosed } }
        .filter { !$0.isEmpty }
}

/// The web's bulk confirmations for a status change or ending discussions
/// (`handleBulkUpdateConfirmationModal`,
/// `handleBulkEndDiscussionConfirmationModal`, sell-grid-actions.service.ts).
/// Inquiries still asking for access are dropped from either, and the
/// message says so (`getPreAndPostPursuitDeals`).
struct BulkStatusCopy: Equatable {
    /// Who the change actually goes to.
    let deals: [SellsideDeal]
    let title: String
    let message: String
    let confirm: String

    /// Mark everyone as `option`.
    init(updating selected: [SellsideDeal], to option: DealStatusUpdateOption, memberType: String) {
        let (inquiries, deals) = Self.split(selected)
        self.deals = deals
        title = "Update Deal Status"
        message = (inquiries ? Self.inquiryNote(ending: false) : "")
            + "You're about to mark \(deals.count) \(memberType) \(Self.members(deals.count)) as \(option.label)."
        confirm = "Update \(deals.count) \(Self.members(deals.count).capitalized)"
    }

    /// End discussions with everyone.
    init(endingDiscussionsWith selected: [SellsideDeal], memberType: String) {
        let (inquiries, deals) = Self.split(selected)
        self.deals = deals
        title = "End Discussions"
        message = (inquiries ? Self.inquiryNote(ending: true) : "")
            + "You're about to end discussions with \(deals.count) \(memberType) \(Self.members(deals.count))."
        confirm = "End \(deals.count) Discussion\(deals.count == 1 ? "" : "s")"
    }

    private static func split(_ selected: [SellsideDeal]) -> (hasInquiries: Bool, rest: [SellsideDeal]) {
        let rest = selected.filter { $0.supplyStatus != .targetRequestedAccess }
        return (rest.count < selected.count, rest)
    }

    private static func inquiryNote(ending: Bool) -> String {
        ending
            ? "Inbound Inquiries need to be reviewed separately. We've removed them from your selection — you'll only end discussions with the remaining members.\n\n"
            : "Inbound Inquiries need to be accepted before updating their status. We've removed them from your selection — only the remaining members will be updated.\n\n"
    }

    private static func members(_ count: Int) -> String { count == 1 ? "member" : "members" }
}

/// `handleBulkPassOnRecommendedMemberConfirmationModal`.
struct RecommendedPassCopy: Equatable {
    let message: String
    let confirm: String

    init(count: Int) {
        let noun = count == 1 ? "member" : "members"
        message = "You're about to pass on \(count) \(noun)."
        confirm = "Pass on \(count) \(noun.capitalized)"
    }
}
