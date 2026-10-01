//
//  ProjectStatusDetail.swift
//  Axial Mobile
//

import Foundation

/// What the status popover shows: one row for where the project stands, and —
/// while it's active — one for how it's being shared.
///
/// Mirrors `updateHoverData` in fe-app's sell-intent-status-tag.component.ts,
/// which builds the same two rows for the web's hover card.
struct ProjectStatusDetail: Equatable {
    struct Row: Identifiable, Equatable {
        let id: String
        let systemImage: String
        let palette: TagPalette
        let title: String
        let subtitle: String?
    }

    let rows: [Row]

    /// `now` is injected so the relative subtitles are testable.
    init(project: ProjectDetail, now: Date = .now) {
        var rows: [Row] = [
            Row(
                id: "status",
                systemImage: project.supplyState.detailIcon,
                palette: StatusTag.palette(for: project.supplyState),
                title: project.supplyState.label,
                subtitle: Self.statusSubtitle(project: project, now: now)
            )
        ]

        // Web only offers the sharing row on an active project — the settings
        // are meaningless on a draft or an archived deal.
        if project.intentState == .active {
            rows.append(Self.sharingRow(project: project, now: now))
        }

        self.rows = rows
    }

    // MARK: - Status row

    /// Mirrors `getSubtitle`: some statuses read as a date ("Since December 11,
    /// 2025"), the rest as an age ("43 days on Axial"). A status with no date
    /// field, or with the field unset, gets no subtitle at all.
    static func statusSubtitle(project: ProjectDetail, now: Date) -> String? {
        guard let field = project.supplyState.statusDateField,
              let date = project.date(for: field) else { return nil }

        if project.supplyState.usesShortDateSubtitle {
            return "Since \(date.formatted(.dateTime.month(.wide).day().year()))"
        }
        let days = daysBetween(date, and: now)
        return "\(days) \(days == 1 ? "day" : "days") on Axial"
    }

    /// Web's `calculateDaysDifference`: absolute difference, rounded up. The
    /// absolute value means a future date reads as a positive age, which is
    /// odd but faithful — these fields are always in the past in practice.
    static func daysBetween(_ date: Date, and now: Date) -> Int {
        let seconds = abs(now.timeIntervalSince(date))
        return Int(ceil(seconds / 86_400))
    }

    // MARK: - Sharing row

    /// Mirrors `currentSharingSetting` + `sharingSettingsConfig`.
    ///
    /// One deviation: web also requires `account.can_enable_inbound_inquiry`
    /// before showing the inbound-inquiry row. Mobile doesn't fetch the
    /// account, so it goes on the project's own flag — in practice a project
    /// can only have inbound inquiry enabled if its account could enable it.
    /// See docs/CHALLENGES.md #14.
    static func sharingRow(project: ProjectDetail, now: Date) -> Row {
        if project.isInboundInquiryEnabled {
            return Row(
                id: "sharing",
                systemImage: "tray.and.arrow.down",
                palette: .plain,
                title: "Inbound Inquiry",
                subtitle: project.inboundInquiryDate.map {
                    "Active since \($0.formatted(.dateTime.month(.wide).day().year()))"
                }
            )
        }

        if project.autoshareState == .enabled {
            let days = smartshareExpiryInDays(project: project, now: now)
            return Row(
                id: "sharing",
                systemImage: "wand.and.sparkles",
                palette: .blue,
                title: "SmartShare",
                subtitle: days.map { "Active for \($0) more \($0 == 1 ? "day" : "days")" }
            )
        }

        return Row(
            id: "sharing",
            systemImage: "checklist",
            palette: .plain,
            title: "Manual Review",
            subtitle: nil
        )
    }

    /// Web's `smartshareExpiryInDays`: days remaining, rounded up, floored at
    /// zero; nil when SmartShare isn't running.
    static func smartshareExpiryInDays(project: ProjectDetail, now: Date) -> Int? {
        guard project.autoshareState == .enabled, let expiry = project.autoshareExpiresAt else {
            return nil
        }
        let days = expiry.timeIntervalSince(now) / 86_400
        return days > 0 ? Int(ceil(days)) : 0
    }
}

// MARK: - Which date a status reads

/// The milestone a status is dated by. Mirrors `dateField` in
/// `SELL_INTENT_STATUS_OPTIONS`.
enum StatusDateField {
    case lastDraft
    case inReview
    case inMarket
    case underLoi
    case inboundInquiry
}

extension ProjectDetail {
    func date(for field: StatusDateField) -> Date? {
        switch field {
        case .lastDraft: lastDraftDate
        case .inReview: inReviewDate
        case .inMarket: inMarketDate
        case .underLoi: underLoiDate
        case .inboundInquiry: inboundInquiryDate
        }
    }
}

extension SupplyState {
    /// `SELL_INTENT_STATUS_OPTIONS[state].dateField`.
    ///
    /// `under_review` reading `inboundInquiryDate` looks like a web slip — the
    /// other statuses each read their own milestone — but it's mirrored rather
    /// than corrected, so the two apps can't disagree about a date.
    var statusDateField: StatusDateField? {
        switch self {
        case .draft: .lastDraft
        case .underReview: .inboundInquiry
        case .inMarket: .inMarket
        case .reviewingLois: .inReview
        case .underLoi: .underLoi
        case .readyToShare, .pendingClose, .closed, .onHold, .dead, .unknown: nil
        }
    }

    /// `shortDateSubtitle` — these two read as a date rather than an age.
    var usesShortDateSubtitle: Bool {
        self == .draft || self == .underLoi
    }

    /// SF Symbol standing in for the web's Remix `iconName`.
    var detailIcon: String {
        switch self {
        case .draft: "circle"
        case .underReview: "magnifyingglass.circle"
        case .readyToShare: "checkmark.circle"
        case .inMarket: "smallcircle.filled.circle"
        case .reviewingLois: "doc.text.magnifyingglass"
        case .underLoi: "checkmark.shield"
        case .pendingClose: "clock.arrow.circlepath"
        case .closed: "trophy"
        case .onHold: "pause.circle"
        case .dead: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }
}
