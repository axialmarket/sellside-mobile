//
//  ProjectActionItems.swift
//  Axial Mobile
//

import Foundation

/// One thing the seller should do next, shown at the top of the dashboard.
///
/// Mirrors fe-app's `SellDashboardStore.actionItems` (sell-dashboard.store.ts)
/// and `ActionItemKey` / `ACTION_ITEM_PRIORITY` (action-items.model.ts). The
/// derivation is all here, as pure data; the view only renders it and routes
/// the `control`.
struct ProjectActionItem: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case approveMembers = "approve_members"
        case reviewNdaRedlines = "review_nda_redlines"
        case updateProjectStatus = "update_project_status"
        case uploadCim = "upload_cim"
        case sendCim = "send_cim"
        case updateStaleFinancials = "update_stale_financials"
        case enableFollowUp = "enable_follow_up"
    }

    /// What tapping the item does.
    enum Control: Equatable {
        /// Push the members it's about.
        case segment(DealSegment)
        /// One status change, named by the CTA — the deal-driven status prompt.
        case status(ProjectAction, ctaLabel: String)
        /// Pick any available status — the stale-project nudge. The web
        /// renders its status menu here.
        case statusMenu
        /// Opens project setup on the step that fixes it — the web's
        /// `?openFinancialsModal`, CIM and follow-up deep links.
        case setup(SetupStep)
    }

    let kind: Kind
    let title: String
    let description: String
    let control: Control

    /// Kind alone isn't enough: Update Project Status has two variants with
    /// different controls, and a switch between them should read as one item
    /// leaving and another arriving, not one row changing type in place.
    var id: String {
        switch control {
        case .status: "\(kind.rawValue)-prompt"
        default: kind.rawValue
        }
    }

    var systemImage: String {
        switch kind {
        case .approveMembers: "person.badge.clock"
        case .reviewNdaRedlines: "doc.badge.ellipsis"
        case .updateProjectStatus: "arrow.triangle.2.circlepath"
        case .uploadCim: "arrow.up.doc"
        case .sendCim: "paperplane"
        case .updateStaleFinancials: "chart.bar.doc.horizontal"
        case .enableFollowUp: "envelope.badge"
        }
    }
}

// MARK: - Derivation

extension ProjectActionItem {
    /// Days without a supply-side action before the stale nudge appears.
    /// Matches the first tier of the backend's stale-deal email
    /// (`STALE_DEAL_THRESHOLD_DAYS`), so the nudge and the email track the
    /// same deals.
    static let staleThresholdDays = 60

    /// States that get action items at all: a live deal that isn't far
    /// downfunnel. `ACTION_ITEM_SUPPLY_STATES`. Fails closed — `.unknown`
    /// isn't here, and treating unknown as permissive is what let these
    /// prompts leak onto closed and dead deals on the web.
    static let allowedStates: Set<SupplyState> = [.inMarket, .readyToShare]

    /// States where the deal-driven status prompt stays hidden. It has its
    /// own gate because it must survive downfunnel states — a project that
    /// went Under LOI and then had a deal close is exactly its case.
    /// `STATUS_PROMPT_EXCLUDED_SUPPLY_STATES`, less the states mobile has no
    /// case for (`auto_draft`, `rejected_approval`), plus `.unknown`.
    static let statusPromptExcludedStates: Set<SupplyState> = [
        .onHold, .dead, .draft, .underReview, .unknown,
    ]

    /// Every applicable item, highest priority first.
    ///
    /// Not mirrored: "Enrich your project details" (`ADD_ADDITIONAL_DATA`).
    /// It reads the CIM-extraction diff the web computes in `SellIntentStore`,
    /// which mobile doesn't fetch.
    static func items(for dashboard: ProjectDashboard, now: Date = .now) -> [ProjectActionItem] {
        let project = dashboard.project
        let allowed = allowedStates.contains(project.supplyState)

        let candidates: [Kind: ProjectActionItem?] = [
            .approveMembers: allowed ? approveMembers(dashboard) : nil,
            .reviewNdaRedlines: allowed ? reviewNdaRedlines(dashboard) : nil,
            .updateProjectStatus: statusPrompt(dashboard) ?? staleNudge(project, now: now),
            .uploadCim: allowed ? uploadCim(dashboard) : nil,
            .sendCim: allowed ? sendCim(dashboard) : nil,
            .updateStaleFinancials: allowed ? staleFinancials(project, now: now) : nil,
            .enableFollowUp: allowed ? enableFollowUp(project) : nil,
        ]

        // `ACTION_ITEM_PRIORITY`. Follow-up is a setup nudge rather than
        // something a member is waiting on, so it sorts last.
        return Kind.allCases.compactMap { candidates[$0] ?? nil }
    }

    private static func approveMembers(_ dashboard: ProjectDashboard) -> ProjectActionItem? {
        let count = DealSegment.pendingApproval.deals(in: dashboard).count
        guard count > 0 else { return nil }
        return ProjectActionItem(
            kind: .approveMembers,
            title: "Review \(members(count)) awaiting approval",
            description: "\(members(count)) requested approval and \(count == 1 ? "is" : "are") awaiting your review.",
            control: .segment(.pendingApproval)
        )
    }

    private static func reviewNdaRedlines(_ dashboard: ProjectDashboard) -> ProjectActionItem? {
        let count = DealSegment.ndaRedlines.deals(in: dashboard).count
        guard count > 0 else { return nil }
        return ProjectActionItem(
            kind: .reviewNdaRedlines,
            title: "Review NDA redlines from \(members(count))",
            description: "A member proposed changes to your NDA. Review the redlines to keep the deal moving.",
            control: .segment(.ndaRedlines)
        )
    }

    /// A member is at LOI Executed or Successfully Closed, so the project's
    /// own status is out of date. Wins over the stale nudge, and Closed wins
    /// over Under LOI. Only asks for a status *ahead* of where the project
    /// already is — a project at Pending Close is never asked to step back to
    /// Under LOI. `statusPrompt` / `STATUS_PROMPTS`; copy and CTA labels match
    /// the Interested tab's own prompt, so the two read as one flow.
    private static func statusPrompt(_ dashboard: ProjectDashboard) -> ProjectActionItem? {
        let state = dashboard.project.supplyState
        guard !statusPromptExcludedStates.contains(state) else { return nil }

        // `STATUS_PROMPT_PROGRESS`: 1 = paused for an LOI, 2 = closed.
        let reached = switch state {
        case .underLoi: 1
        case .pendingClose, .closed: 2
        default: 0
        }
        // Only interested members count — a seller can mark anyone's status.
        let interested = dashboard.interestedDeals

        if reached < 2, interested.contains(where: { $0.supplyStatus == .markedClosed }) {
            return ProjectActionItem(
                kind: .updateProjectStatus,
                title: "Update your project status",
                description: "A member is Successfully Closed. Update your project to Successfully Closed and take it out of market.",
                control: .status(.closed, ctaLabel: "Project is Closed")
            )
        }
        if reached < 1, interested.contains(where: { $0.supplyStatus == .markedExecutedLoi }) {
            return ProjectActionItem(
                kind: .updateProjectStatus,
                title: "Update your project status",
                description: "A member is at LOI Executed. Update your project to Under LOI and pause new interest.",
                control: .status(.underLoi, ctaLabel: "Pause New Interest")
            )
        }
        return nil
    }

    /// An active project that's gone quiet. Reads the legacy `intent_state`,
    /// not `supply_state`, to match the backend email's population.
    /// `shouldUpdateProjectStatus`.
    private static func staleNudge(_ project: ProjectDetail, now: Date) -> ProjectActionItem? {
        guard project.intentState == .active,
              let days = project.daysSinceLastActivity(now: now),
              days >= staleThresholdDays else { return nil }
        return ProjectActionItem(
            kind: .updateProjectStatus,
            title: "Update your project status",
            description: "This project has been quiet for \(days) days — update its status so members know where things stand.",
            control: .statusMenu
        )
    }

    /// A member has signed the NDA but there's no CIM to send them. Uses the
    /// signature record, so it holds once the deal moves further on. A waived
    /// CIM counts as none. `hasUploadCimAction`.
    private static func uploadCim(_ dashboard: ProjectDashboard) -> ProjectActionItem? {
        let cimType = dashboard.project.cimType
        let noCim = cimType == nil || cimType == .waive
        guard noCim, dashboard.deals.contains(where: \.hasSignedNda) else { return nil }
        return ProjectActionItem(
            kind: .uploadCim,
            title: "Upload your CIM",
            description: "Members have signed your NDA and are ready to review your CIM. Upload it to keep your deal moving.",
            control: .setup(.cimSummaryMaterials)
        )
    }

    /// Only once a CIM exists to send, so it follows Upload CIM.
    private static func sendCim(_ dashboard: ProjectDashboard) -> ProjectActionItem? {
        guard dashboard.project.hasCim else { return nil }
        let count = DealSegment.awaitingCim.deals(in: dashboard).count
        guard count > 0 else { return nil }
        return ProjectActionItem(
            kind: .sendCim,
            title: "Send the CIM to \(members(count))",
            description: "\(members(count)) signed the NDA and \(count == 1 ? "is" : "are") awaiting the CIM.",
            control: .segment(.awaitingCim)
        )
    }

    /// Copy is fixed and names no years, so it holds however many are stale.
    private static func staleFinancials(_ project: ProjectDetail, now: Date) -> ProjectActionItem? {
        guard !project.staleFinancialYears(now: now).isEmpty else { return nil }
        return ProjectActionItem(
            kind: .updateStaleFinancials,
            title: "Update Stale Financials",
            description: "Your projected financials are now out of date since that year has passed — please update them to reflect actuals or clear those values",
            control: .setup(.financials)
        )
    }

    private static func enableFollowUp(_ project: ProjectDetail) -> ProjectActionItem? {
        guard !project.hasFollowUp else { return nil }
        return ProjectActionItem(
            kind: .enableFollowUp,
            title: "Enable automatic follow-up note",
            description: "Automatically send a follow-up note to contacted members.",
            control: .setup(.messaging)
        )
    }

    /// "1 member", "3 members".
    private static func members(_ count: Int) -> String {
        "\(count) member\(count == 1 ? "" : "s")"
    }
}
