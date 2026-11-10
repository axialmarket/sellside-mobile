//
//  ManageProjectMenu.swift
//  Axial Mobile
//

import Foundation

/// What the Manage Project menu offers for a given project.
///
/// Mirrors `manageMenuItems` in fe-app's manage-project.component.ts: the
/// status submenu and Sharing Settings — with the same rules about when
/// Sharing Settings is dropped or greyed out. Edit Project is web-only.
struct ManageProjectMenu: Equatable {
    /// Status changes, grouped the way the web separates them.
    let statusGroups: [[ProjectAction]]
    /// Web splices the item out entirely on an archived project rather than
    /// disabling it — there's nothing to configure once a deal is off market.
    let showsSharingSettings: Bool
    let sharingSettingsIsDisabled: Bool

    init(project: ProjectDetail) {
        statusGroups = ProjectAction.menu(for: project.supplyState)
        showsSharingSettings = !project.isArchived
        sharingSettingsIsDisabled = project.sharingSettingsIsDisabled
    }
}

extension ProjectDetail {
    /// `Intent.isArchived` — an archived, under-LOI or closed project is off
    /// market, whatever its sell-side status says.
    var isArchived: Bool {
        intentState == .archived || intentState == .underLoi || intentState == .closed
    }

    /// Web: `!isComplete || (!account.can_share_teasers && !isApproved())`,
    /// then additionally greyed when autoshare is ineligible.
    ///
    /// Mobile doesn't fetch the account, so the middle clause is dropped —
    /// which can leave the item tappable where the web would grey it, for an
    /// unapproved project on an account that can't share teasers. See
    /// docs/CHALLENGES.md #14.
    var sharingSettingsIsDisabled: Bool {
        !isComplete || autoshareState == .ineligible
    }

    /// Web disables Copy Deal Link until the project is complete — there's
    /// nothing worth linking to before then.
    var canCopyDealLink: Bool {
        isComplete
    }
}
