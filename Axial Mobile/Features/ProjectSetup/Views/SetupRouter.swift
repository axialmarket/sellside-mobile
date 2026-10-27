//
//  SetupRouter.swift
//  Axial Mobile
//

import SwiftUI

/// The wizard's navigation stack — `ProjectSetupNavigationService`.
///
/// The navigator is the root. Every step lives in one pushed pager
/// (`SetupStepPager`), and Previous or Next just changes `currentStep`, so
/// the page slides sideways in place rather than pushing. A back swipe from any step therefore lands on the navigator.
/// Review pushes on top of whatever opened it, so swiping back from review
/// returns the member to exactly where they were.
@Observable
final class SetupRouter {
    var path: [SetupRoute] = []
    var section: SetupSection = .dealDetails
    /// The pager's page, and the step drawn selected in the navigator.
    var currentStep: SetupStep? {
        didSet {
            if let currentStep { section = currentStep.section }
        }
    }
    /// Set when a route was chosen to fix something, so that page scrolls to
    /// its first error. Observed, so a page that's already showing reacts.
    private(set) var scrollToFirstError: SetupStep?
    /// The ToS notice asks for attention once (`tosNoticePulseRequested`).
    var pulseTosNotice = false

    /// From the navigator, the incomplete list or a review row: show the
    /// pager on this step, dropping anything stacked above it.
    func open(_ step: SetupStep, toFix: Bool = false) {
        currentStep = step
        scrollToFirstError = toFix ? step : nil
        if path != [.steps] {
            path = [.steps]
        }
    }

    enum PageDirection { case forward, backward }

    /// Which way the last page turn went — which edge the new page slides
    /// in from.
    private(set) var pageDirection: PageDirection = .forward

    /// Previous and Next: a page turn. The direction is set a frame ahead of
    /// the change, so the outgoing page already carries the matching removal
    /// transition when it leaves — otherwise flipping from Next to Previous
    /// slides the old page out the wrong way.
    func page(to step: SetupStep, animated: Bool) {
        let sequence = SetupStep.allCases
        let forward = (sequence.firstIndex(of: step) ?? 0) > (currentStep.flatMap { sequence.firstIndex(of: $0) } ?? 0)
        pageDirection = forward ? .forward : .backward
        guard animated else {
            currentStep = step
            return
        }
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.35)) { currentStep = step }
        }
    }

    func review() {
        path.append(.review)
    }

    func consumeScrollRequest(for step: SetupStep) -> Bool {
        guard scrollToFirstError == step else { return false }
        scrollToFirstError = nil
        return true
    }

    /// Back to the navigator.
    func popToNavigator() {
        path = []
    }
}

/// What happened when setup closed, so the presenter can refresh.
enum SetupExit: Equatable {
    case closed
    case shared(SmartShare: Bool)
    case submittedForApproval
    case saved
}
