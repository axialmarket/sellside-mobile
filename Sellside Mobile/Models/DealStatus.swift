//
//  DealStatus.swift
//  Sellside Mobile
//

import Foundation

/// A deal's supply-side status. Mirrors `SUPPLY_STATUS` and
/// `SUPPLY_STATUS_LABELS` in fe-app `deal.constants.ts`.
///
/// Two cases are display-only — the backend never sends them. `teaserOpened`
/// and `referralReceived` are virtual statuses the web derives from other
/// fields; see `SellsideDeal.displayStatus`. They live in this enum because
/// the web's label table is keyed the same way.
nonisolated enum DealStatus: String, Decodable, Hashable, CaseIterable {
    case notShared = "not_shared"
    case sentLocked = "sent_locked"
    case targetRequestedAccess = "target_requested_access"
    case targetDeclinedLocked = "target_declined_locked"
    case rejectedAccess = "rejected_access"
    case removedLocked = "removed_locked"
    case recommended
    case sentTeaser = "sent_teaser"
    case targetPursued = "target_pursued"
    case targetDeclined = "target_declined"
    case sentNda = "sent_nda"
    case markedSentNda = "marked_sent_nda"
    case targetViewedNda = "target_viewed_nda"
    case targetSignedNda = "target_signed_nda"
    case markedNdaSigned = "marked_nda_signed"
    case sentCim = "sent_cim"
    case targetViewedCim = "target_viewed_cim"
    case markedSentCim = "marked_sent_cim"
    case markedReceivedIoi = "marked_received_ioi"
    case markedReceivedLoi = "marked_received_loi"
    case markedExecutedLoi = "marked_executed_loi"
    case markedTargetDeclined = "marked_target_declined"
    case markedClosed = "marked_successfully_closed"
    case endedDiscussions = "ended_discussions"
    case targetEndedDiscussions = "target_ended_discussions"
    case targetExpired = "target_expired"
    case archivedLocked = "archived_locked"

    // Deprecated on both ends, but existing deals still sit in them.
    case markedManagementMeetingScheduled = "marked_management_meeting_scheduled"
    case markedManagementMeetingHeld = "marked_management_meeting_held"

    /// Display-only, derived rather than stored.
    case teaserOpened = "teaser_opened"
    case referralReceived = "referral_received"

    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DealStatus(rawValue: raw) ?? .unknown
    }

    /// `SUPPLY_STATUS_LABELS`.
    var label: String {
        switch self {
        case .notShared: "Deal Not Shared"
        case .sentLocked: "Sent Locked Deal"
        case .targetRequestedAccess: "Inquiry Received"
        case .referralReceived: "Referral Received"
        case .targetDeclinedLocked: "Member Declined Access"
        case .rejectedAccess: "Denied Access"
        case .removedLocked: "Removed Locked Deal"
        case .recommended: "Recommended by Axial"
        case .sentTeaser: "Teaser Sent"
        case .targetPursued: "Pursued"
        case .targetDeclined, .markedTargetDeclined: "Member Declined"
        case .sentNda, .markedSentNda: "NDA Sent"
        case .targetViewedNda: "NDA Viewed"
        case .targetSignedNda, .markedNdaSigned: "NDA Signed"
        case .sentCim, .markedSentCim: "CIM Sent"
        case .targetViewedCim: "CIM Viewed"
        case .markedReceivedIoi: "IOI Received"
        case .markedReceivedLoi: "LOI Received"
        case .markedExecutedLoi: "LOI Executed"
        case .markedManagementMeetingScheduled: "Management Mtg Scheduled"
        case .markedManagementMeetingHeld: "Management Mtg Held"
        case .markedClosed: "Successfully Closed"
        case .endedDiscussions, .targetEndedDiscussions: "Discussions Ended"
        case .targetExpired: "Never Replied"
        case .teaserOpened: "Teaser Opened"
        case .archivedLocked: "Archived"
        case .unknown: "Unknown"
        }
    }
}
