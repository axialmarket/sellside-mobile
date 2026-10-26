//
//  SetupRouter.swift
//  Axial Mobile
//

import SwiftUI

/// The wizard's navigation stack — `ProjectSetupNavigationService`.
///
/// The navigator is always the root, and at most one step sits on it: Next
/// and Previous *replace* the step rather than push another, so a back
/// swipe from any step lands on the navigator, never on the step before.
/// Review pushes on top of whichever step (or the navigator) opened it, so
/// swiping back from review returns the member to exactly where they were.
@Observable
final class SetupRouter {
    var path: [SetupRoute] = []
    var section: SetupSection = .dealDetails
    /// Drawn selected in the navigator.
    private(set) var currentStep: SetupStep?
    /// Set when a route was chosen to fix something, so the step opens
    /// scrolled to its first error.
    private(set) var scrollToFirstError: SetupStep?
    /// The ToS notice asks for attention once (`tosNoticePulseRequested`).
    var pulseTosNotice = false

    var onTopStep: SetupStep? {
        if case .step(let step)? = path.last { return step }
        return nil
    }

    func open(_ step: SetupStep, toFix: Bool = false) {
        currentStep = step
        section = step.section
        scrollToFirstError = toFix ? step : nil
        path = [.step(step)]
    }

    /// Next: replaces the step in place, which pushes from the trailing edge.
    func next(to step: SetupStep) {
        open(step)
    }

    /// Previous: slips the earlier step in underneath without animation,
    /// then pops to it — so it slides in from the leading edge, the way
    /// going back should, and the stack is left as [navigator, step].
    func previous(to step: SetupStep, from current: SetupStep) {
        currentStep = step
        section = step.section
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { path = [.step(step), .step(current)] }
        Task { @MainActor in
            path.removeLast()
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
