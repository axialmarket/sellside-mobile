//
//  SetupNavigatorView.swift
//  Axial Mobile
//

import SwiftUI

/// The wizard's landing screen — the web's sidenav, given the whole screen.
/// A segmented control for the three sections, then the section's steps as
/// the web's radio-button rows (icon, name, "2 of 5"), each pushing its step.
struct SetupNavigatorView: View {
    @Binding var section: SetupSection
    /// The step the member was last on, drawn selected like the web's
    /// current step.
    let currentStep: SetupStep?
    let onSelect: (SetupStep) -> Void

    @Environment(ProjectSetupSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Section", selection: $section.animation(reduceMotion ? nil : .snappy)) {
                    ForEach(SetupSection.allCases) { section in
                        Text(section.displayName).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setup-section-picker")

                sectionHeader

                VStack(spacing: 10) {
                    ForEach(session.steps(in: section)) { step in
                        SetupStepRow(
                            step: step,
                            progress: session.progress(for: step),
                            showingErrors: session.showsValidationErrors,
                            isCurrent: step == currentStep
                        ) {
                            onSelect(step)
                        }
                        .transition(.opacity)
                    }
                }
                .id(section)
                .transition(.opacity)

                if session.context.isAutoDrafting {
                    AutodraftNotice()
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AxialColor.layer2)
        // Swiping across the list moves between sections, as the segmented
        // control does — a second way to reach the same three pages.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                    let all = SetupSection.allCases
                    guard let index = all.firstIndex(of: section) else { return }
                    let target = value.translation.width < 0 ? index + 1 : index - 1
                    guard all.indices.contains(target) else { return }
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .snappy) { section = all[target] }
                }
        )
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .foregroundStyle(session.sectionHasError(section) ? AxialColor.error : AxialColor.brandPrimary)
            Text(section.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AxialColor.textPrimary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// `axl-radio-button radioStyle="button"` with the step's state icon and
/// supporting text. Red once validation is showing and the step is invalid.
struct SetupStepRow: View {
    let step: SetupStep
    let progress: StepProgress
    let showingErrors: Bool
    let isCurrent: Bool
    let action: () -> Void

    private var indicator: StepProgress.Indicator {
        progress.indicator(showingErrors: showingErrors)
    }

    private var hasError: Bool { indicator == .error }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                StepIndicatorIcon(indicator: indicator)
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                    Text(progress.text)
                        .font(.subheadline)
                        .foregroundStyle(hasError ? AxialColor.errorText : AxialColor.textSecondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? AxialColor.brandSubtle : AxialColor.layer1, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: isCurrent || hasError ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(CardButtonStyle())
        .animation(.easeOut(duration: 0.2), value: indicator)
        .animation(.easeOut(duration: 0.2), value: progress)
        .accessibilityElement(children: .combine)
        .accessibilityHint(progress.text)
        .accessibilityIdentifier("setup-step-\(step.routeName)")
    }

    private var borderColor: Color {
        if hasError { return AxialColor.error }
        return isCurrent ? AxialColor.brandPrimary : AxialColor.border
    }
}

/// circle-line, progress-4-line, checkbox-circle-line, error-warning-line.
struct StepIndicatorIcon: View {
    let indicator: StepProgress.Indicator

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 28)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch indicator {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .complete: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch indicator {
        case .notStarted, .inProgress: AxialColor.textPlaceholder
        case .complete: AxialColor.success
        case .error: AxialColor.error
        }
    }
}

/// `showAutodraftNotification`'s banner.
struct AutodraftNotice: View {
    var body: some View {
        SetupNotice(
            style: .info,
            title: "Autodraft in Progress",
            message: "We're analyzing your documents and completing the deal details. This process usually takes about 5 minutes. You'll be able to review and finalize the project once it's complete."
        )
    }
}

/// `axl-inline-notification`: a tinted callout with an icon.
struct SetupNotice: View {
    enum Style {
        case info, neutral, warning, error

        var tint: Color {
            switch self {
            case .info: AxialColor.brandPrimary
            case .neutral: AxialColor.textSecondary
            case .warning: TagPalette.yellow.foreground
            case .error: AxialColor.errorText
            }
        }

        var background: Color {
            switch self {
            case .info: AxialColor.brandSubtle
            case .neutral: AxialColor.layer3
            case .warning: TagPalette.yellow.background
            case .error: AxialColor.errorSubtle
            }
        }

        var systemImage: String {
            switch self {
            case .info, .neutral: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "exclamationmark.circle.fill"
            }
        }
    }

    let style: Style
    var title: String?
    var message: String?
    var bullets: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.tint)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                }
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(bullet)
                    }
                    .font(.footnote)
                }
            }
            .foregroundStyle(AxialColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
