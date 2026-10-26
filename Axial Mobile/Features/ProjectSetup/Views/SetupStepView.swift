//
//  SetupStepView.swift
//  Axial Mobile
//

import SwiftUI

/// One step, full screen — `ProjectSetupContentComponent` plus
/// `ProjectSetupStepActionsComponent`. The step's segments scroll; Previous
/// and Next sit in the bottom bar, named for the steps they go to, and the
/// last step's Next is the review button.
struct SetupStepView: View {
    let step: SetupStep
    let onReview: () -> Void

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
            .onAppear {
                guard router.consumeScrollRequest(for: step),
                      let field = firstInvalidField else { return }
                // After the push settles, so the scroll isn't lost to it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
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
                    Button {
                        Haptics.selection()
                        router.previous(to: previous, from: step)
                    } label: {
                        Label(previous.displayName, systemImage: "arrow.left")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .tint(AxialColor.textPrimary)
                    .accessibilityIdentifier("setup-previous")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                if let next = session.context.next(after: step) {
                    Button {
                        Haptics.selection()
                        router.next(to: next)
                    } label: {
                        HStack(spacing: 6) {
                            Text(next.displayName).lineLimit(1)
                            Image(systemName: "arrow.right")
                        }
                    }
                    .tint(AxialColor.brandPrimary)
                    .accessibilityIdentifier("setup-next")
                } else {
                    Button(session.reviewLabel, action: onReview)
                        .buttonStyle(.borderedProminent)
                        .tint(AxialColor.brandPrimary)
                        .disabled(session.context.isAutoDrafting)
                        .accessibilityIdentifier("setup-review")
                }
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
