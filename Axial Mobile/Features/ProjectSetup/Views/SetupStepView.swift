//
//  SetupStepView.swift
//  Axial Mobile
//

import SwiftUI

/// The steps, one page at a time — `ProjectSetupContentComponent` plus
/// `ProjectSetupStepActionsComponent`. Previous and Next in the bottom bar
/// slide to the neighbouring step; both are named for the step they go to.
/// The last step's Next is the review button.
///
/// One pushed screen for all of them, so the title, the bar and the back
/// swipe to the navigator stay put while only the page changes.
struct SetupStepPager: View {
    let onReview: () -> Void

    @Environment(ProjectSetupSession.self) private var session
    @Environment(SetupRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: SetupStep {
        router.currentStep ?? session.context.sequence.first ?? .companyBasics
    }

    /// Forward comes in from the trailing edge and pushes the old page out
    /// the leading one; backward is the mirror.
    private var pageTransition: AnyTransition {
        let forward = router.pageDirection == .forward
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                           removal: .move(edge: forward ? .leading : .trailing))
    }

    var body: some View {
        // One page at a time, swapped with a slide — no swiping between
        // steps. A swipe moved the page but not the bar buttons, which only
        // morph their titles on a tap, so the buttons are the only way to
        // turn the page. Each page starts at the top, as the web's do.
        ZStack {
            SetupStepView(step: step)
                .id(step)
                .transition(pageTransition)
        }
        .background(AxialColor.layer2)
        .onChange(of: step) { _, _ in
            // A half-typed field on the page left behind shouldn't keep the
            // keyboard up over the new one.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .navigationTitle(step.displayName)
        .navigationSubtitle("\(step.section.displayName) · \(session.progress(for: step).text)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.isAutosaveEnabled {
                ToolbarItem(placement: .topBarTrailing) { AutosaveIndicator() }
            }
            if let previous = session.context.previous(before: step) {
                ToolbarItem(placement: .bottomBar) {
                    StepNavButton(title: previous.displayName, direction: .previous) {
                        Haptics.selection()
                        router.page(to: previous, animated: !reduceMotion)
                    }
                    .accessibilityIdentifier("setup-previous")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                if let next = session.context.next(after: step) {
                    StepNavButton(title: next.displayName, direction: .next) {
                        Haptics.selection()
                        router.page(to: next, animated: !reduceMotion)
                    }
                    .accessibilityIdentifier("setup-next")
                } else {
                    Button(action: onReview) {
                        Text(session.reviewLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AxialColor.brandPrimary)
                    .disabled(session.context.isAutoDrafting)
                    .accessibilityIdentifier("setup-review")
                }
            }
        }
    }
}

/// Previous or Next: a small chevron beside the step's name, mirrored so
/// the pair reads as one control split across the bar.
private struct StepNavButton: View {
    enum Direction { case previous, next }

    let title: String
    let direction: Direction
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if direction == .previous { chevron }
                Text(title)
                    .lineLimit(1)
                if direction == .next { chevron }
            }
            .font(.subheadline.weight(.medium))
        }
        .tint(direction == .next ? AxialColor.brandPrimary : AxialColor.textPrimary)
        .accessibilityLabel(direction == .next ? "Next: \(title)" : "Previous: \(title)")
    }

    private var chevron: some View {
        Image(systemName: direction == .previous ? "chevron.left" : "chevron.right")
            .font(.caption.weight(.semibold))
    }
}

/// One step's page: its segments, scrolling.
struct SetupStepView: View {
    let step: SetupStep

    @Environment(ProjectSetupSession.self) private var session
    @Environment(SetupRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.context.isLocked(step) {
                        AutodraftNotice()
                    }
                    content
                        .disabled(session.context.isLocked(step))
                        .opacity(session.context.isLocked(step) ? 0.4 : 1)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AxialColor.layer2)
            .onAppear { scrollToErrorIfAsked(proxy) }
            // The page may already be showing when the request comes in —
            // a review row, say — so watch for it too.
            .onChange(of: router.scrollToFirstError) { _, _ in scrollToErrorIfAsked(proxy) }
        }
    }

    private func scrollToErrorIfAsked(_ proxy: ScrollViewProxy) {
        guard router.consumeScrollRequest(for: step), let field = firstInvalidField else { return }
        // After the push or page turn settles, so the scroll isn't lost to it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(reduceMotion ? nil : .easeInOut) {
                proxy.scrollTo(field, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .companyBasics: CompanyBasicsStepView()
        case .capitalRaise: CapitalRaiseStepView()
        case .financials: FinancialsStepView()
        case .customTeaser: CustomTeaserStepView()
        case .nda: NDAStepView()
        case .cimSummaryMaterials: CIMStepView()
        case .sharingSettings: SharingSettingsStepView()
        case .vettingQuestions: EmptyView()
        case .messaging: MessagingStepView()
        case .advancedSharing: DealLinkStepView()
        }
    }

    /// The first field in this step with an error, in validation order —
    /// `findFirstInvalidSegment`, at field rather than segment grain.
    private var firstInvalidField: SetupFieldKey? {
        let prefix = Self.fieldPrefix(step)
        return SetupStepView.fieldOrder(step).first { session.validation.errors[$0] != nil }
            ?? session.validation.errors.keys.filter { $0.rawValue.hasPrefix(prefix) }.sorted { $0.rawValue < $1.rawValue }.first
    }

    private static func fieldPrefix(_ step: SetupStep) -> String {
        switch step {
        case .companyBasics: "companyBasics."
        case .capitalRaise: "capital."
        case .financials: "financials."
        case .nda: "nda."
        case .cimSummaryMaterials: "cim."
        case .sharingSettings: "sharingSettings."
        case .messaging: "messaging."
        default: "\(step.rawValue)."
        }
    }

    /// On-screen order, so "first" means the topmost.
    static func fieldOrder(_ step: SetupStep) -> [SetupFieldKey] {
        typealias C = CompanyBasicsForm.Field
        switch step {
        case .companyBasics:
            return [C.internalName, C.headline, C.description, C.industries, C.roleName, C.exclusiveMandate,
                    C.expectsFeeAdvisor, C.expectsFeeInvestor, C.country, C.state, C.disclosure, C.companyName,
                    C.companyWebsite, C.management, C.licensesRequired, C.licenseDetails, C.realEstateIncluded,
                    C.realEstateDetails, C.fullTimeEmployees, C.partTimeEmployees, C.customerTypes]
        case .capitalRaise:
            typealias K = CapitalRaiseForm.Field
            return [K.capitalType, K.debtTypes, K.useOfFunds, K.maxRange, K.minRange]
        case .financials:
            typealias F = FinancialsForm.Field
            return [F.financials, F.fiscalYearEnd, F.kpis]
        case .nda:
            return [NDAForm.Field.ndaType, NDAForm.Field.linkedNdaUrl]
        case .cimSummaryMaterials:
            typealias M = CIMForm.Field
            return [M.cimType, M.linkedCimUrl, M.smartshareState, M.group, M.calendarLink]
        case .messaging:
            return [MessagingForm.Field.assignedToUser]
        case .sharingSettings:
            return [SharingSettingsForm.Field.blocked]
        default:
            return []
        }
    }
}
