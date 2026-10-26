//
//  ProjectSetupStructure.swift
//  Axial Mobile
//

import Foundation

/// The wizard's three sections. `PROJECT_SETUP_SECTIONS` in
/// project-setup.steps.ts, with the icons from project-setup-sidenav
/// (`SECTION_ICONS`) as SF Symbols.
enum SetupSection: String, CaseIterable, Identifiable, Hashable {
    case dealDetails
    case documents
    case outreach

    var id: Self { self }

    var displayName: String {
        switch self {
        case .dealDetails: "Deal Details"
        case .documents: "Documents"
        case .outreach: "Outreach"
        }
    }

    /// briefcase-line, file-copy-2-line, send-plane-line.
    var systemImage: String {
        switch self {
        case .dealDetails: "briefcase"
        case .documents: "doc.on.doc"
        case .outreach: "paperplane"
        }
    }

    /// Declaration order; `SetupContext.steps(in:)` filters by availability.
    var allSteps: [SetupStep] {
        switch self {
        case .dealDetails: [.companyBasics, .capitalRaise, .financials]
        case .documents: [.customTeaser, .nda, .cimSummaryMaterials]
        case .outreach: [.sharingSettings, .vettingQuestions, .messaging, .advancedSharing]
        }
    }
}

/// One step. Display names and route names are the web's step definitions.
enum SetupStep: String, CaseIterable, Identifiable, Hashable {
    case companyBasics
    case capitalRaise
    case financials
    case customTeaser
    case nda
    case cimSummaryMaterials
    case sharingSettings
    case vettingQuestions
    case messaging
    case advancedSharing

    var id: Self { self }

    var section: SetupSection {
        SetupSection.allCases.first { $0.allSteps.contains(self) }!
    }

    var displayName: String {
        switch self {
        case .companyBasics: "Company Basics"
        case .capitalRaise: "Capital Raise"
        case .financials: "Financials & KPIs"
        case .customTeaser: "Custom Teaser"
        case .nda: "NDA"
        case .cimSummaryMaterials: "CIM / Summary Materials"
        case .sharingSettings: "Sharing Settings"
        case .vettingQuestions: "Vetting Questions"
        case .messaging: "Marketing Settings"
        case .advancedSharing: "Shareable Deal Link"
        }
    }

    /// The `:step` URL segment — kept so a deep link from the web's
    /// `/sell/:id/edit/:section/:step` can land on the same step.
    var routeName: String {
        switch self {
        case .companyBasics: "company-basics"
        case .capitalRaise: "capital"
        case .financials: "financials"
        case .customTeaser: "custom-teaser"
        case .nda: "nda"
        case .cimSummaryMaterials: "cim-summary-materials"
        case .sharingSettings: "sharing-settings"
        case .vettingQuestions: "vetting-questions"
        case .messaging: "marketing-settings"
        case .advancedSharing: "advanced-sharing"
        }
    }
}

/// What step availability depends on — the web's
/// `ProjectSetupDefinitionContext` (intent + session + account), reduced to
/// the facts the `isAvailable` rules read.
struct SetupContext: Equatable {
    var intentType: String
    var supplyState: String
    var intentState: String
    /// `can_manually_share` on the owning account. Unknown on mobile, which
    /// doesn't fetch the account; nil reads as true, the common case.
    var canManuallyShare: Bool?
    /// `NEW_SELLSIDE_PROJECT_SETUP_VETTING_QUESTIONS_STEP` — off by default
    /// on the web, and mobile has no flag client, so off here.
    var vettingQuestionsEnabled = false
    /// Fixed when setup opens — the rollover and fiscal-year rules read it.
    var now: Date = .now
    /// Primary Contact is only required once the account has members.
    var memberCount = 0
    /// `intent.isShared` — gates the close guard and delete warnings.
    var isShared = false
    /// The owning account's permissions (`owned_by_account`). Each defaults
    /// to the common case when the intent doesn't carry it.
    var account = AccountFlags()

    struct AccountFlags: Equatable {
        var canWaiveNDA = false
        var canLinkNDA = false
        var canWaiveCIM = false
        var canLinkCIM = false
        var requireEditableNDA = false
        var canShareTeasers = true
        var canUseAdvancedFilters = true
        var name: String?
    }

    var isCapitalRaise: Bool { intentType == "raise_capital" }
    var isAutoDrafting: Bool { supplyState == "auto_draft" }
    /// `SellsideIntent.isInMarket`: anything past draft.
    var isInMarket: Bool { !intentState.isEmpty && intentState != "draft" }

    func isAvailable(_ step: SetupStep) -> Bool {
        switch step {
        case .capitalRaise: isCapitalRaise
        case .vettingQuestions: vettingQuestionsEnabled
        // The link only exists once the deal is live.
        case .advancedSharing: intentState == "active"
        default: true
        }
    }

    func steps(in section: SetupSection) -> [SetupStep] {
        section.allSteps.filter(isAvailable)
    }

    /// Every available step in wizard order — `stepSequence`.
    var sequence: [SetupStep] {
        SetupSection.allCases.flatMap(steps(in:))
    }

    func previous(before step: SetupStep) -> SetupStep? {
        guard let index = sequence.firstIndex(of: step), index > 0 else { return nil }
        return sequence[index - 1]
    }

    func next(after step: SetupStep) -> SetupStep? {
        guard let index = sequence.firstIndex(of: step), index + 1 < sequence.count else { return nil }
        return sequence[index + 1]
    }
}

/// Where the wizard's navigation stack can go. The navigator is the root;
/// a step is pushed over it (and replaced in place by Next/Previous, so a
/// back swipe always returns to the navigator); the review sits on top of
/// whichever step opened it.
enum SetupRoute: Hashable {
    case step(SetupStep)
    case review
}

/// One step's required-field progress, as the sidenav shows it.
struct StepProgress: Equatable {
    var required: Int
    var completed: Int
    /// A group-level error that isn't a missing field (EBITDA above revenue,
    /// a CIM that needs a signable NDA).
    var hasGroupError = false

    var isIncomplete: Bool { required > 0 && completed < required }
    var isInvalid: Bool { isIncomplete || hasGroupError }

    /// `computeText`: "Optional", "All required steps complete!", "2 of 5".
    var text: String {
        if required == 0 { return "Optional" }
        if completed == required { return "All required steps complete!" }
        return "\(completed) of \(required)"
    }

    enum Indicator: Equatable { case notStarted, inProgress, complete, error }

    /// `computeIcon`. The error state only once validation is showing.
    func indicator(showingErrors: Bool) -> Indicator {
        if showingErrors, isInvalid { return .error }
        if required > 0, completed == required { return .complete }
        if required > 0, completed > 0 { return .inProgress }
        return .notStarted
    }
}

/// The header's completion line. `completionState` in
/// project-setup-form.service.ts, with the copy from
/// project-setup.constants.ts.
struct SetupCompletion: Equatable {
    let incompleteSteps: [SetupStep]

    var isComplete: Bool { incompleteSteps.isEmpty }

    var text: String {
        if isComplete { return "All required steps complete!" }
        let count = incompleteSteps.count
        return "\(count) Required Step\(count > 1 ? "s" : "") Incomplete"
    }
}
