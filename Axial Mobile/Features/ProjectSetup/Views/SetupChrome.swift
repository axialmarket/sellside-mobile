//
//  SetupChrome.swift
//  Axial Mobile
//

import SwiftUI

/// `AutosaveIndicatorComponent`, as a bar button: the status as an icon,
/// and a popover with the last save time. A failed save offers Try Again —
/// the web's click-to-save.
struct AutosaveIndicator: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isShowingDetail = false

    private var status: ProjectSetupSession.AutosaveStatus { session.autosaveStatus }

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            Label(label, systemImage: symbol)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: status == .saving)
        }
        .tint(status == .error ? AxialColor.error : AxialColor.textPrimary)
        .accessibilityLabel(label)
        .accessibilityIdentifier("setup-autosave-indicator")
        .popover(isPresented: $isShowingDetail) {
            detail
                .presentationCompactAdaptation(.popover)
        }
    }

    /// The web's labels; "Autosaved" covers idle too.
    private var label: String {
        switch status {
        case .idle, .saved: "Autosaved"
        case .saving: "Autosaving"
        case .error: "Not saved"
        }
    }

    private var symbol: String {
        switch status {
        case .idle, .saved: "checkmark.icloud"
        case .saving: "arrow.triangle.2.circlepath.icloud"
        case .error: "exclamationmark.icloud"
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status == .error ? AxialColor.errorText : AxialColor.textPrimary)
            if let lastSaved = session.lastSavedAt {
                Text("Last saved \(lastSaved.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AxialColor.textPrimary)
            }
            if status == .error, let error = session.lastSaveError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AxialColor.errorText)
                Button("Try Again") {
                    isShowingDetail = false
                    Task { await session.triggerAutosave() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AxialColor.brandPrimary)
                .controlSize(.small)
            } else {
                Text("All changes are saved automatically.")
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textSecondary)
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }
}

/// `ProjectSetupCompletionPopoverComponent`: the completion line and, when
/// incomplete, a numbered list of steps to fix — each a link there.
struct SetupCompletionList: View {
    let completion: SetupCompletion
    let isAutoDrafting: Bool
    let onSelect: (SetupStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAutoDrafting {
                Label("Autodraft in Progress", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textSecondary)
            } else {
                Label {
                    Text(completion.text)
                } icon: {
                    Image(systemName: completion.isComplete ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(completion.isComplete ? AxialColor.success : AxialColor.error)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AxialColor.textPrimary)

                if !completion.isComplete {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(completion.incompleteSteps.enumerated()), id: \.element) { index, step in
                            Button {
                                onSelect(step)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(index + 1).")
                                        .foregroundStyle(AxialColor.textSecondary)
                                        .monospacedDigit()
                                    Text(step.displayName)
                                        .foregroundStyle(AxialColor.brandPrimary)
                                        .underline()
                                    Text("is incomplete.")
                                        .foregroundStyle(AxialColor.textPrimary)
                                }
                                .font(.footnote)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("setup-incomplete-\(step.routeName)")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 240, alignment: .leading)
    }
}
