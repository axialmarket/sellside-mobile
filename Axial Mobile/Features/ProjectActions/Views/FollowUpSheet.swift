//
//  FollowUpSheet.swift
//  Axial Mobile
//

import SwiftUI

/// Resolves "Enable automatic follow-up note": the Follow-Up Note segment of
/// the web's Marketing Settings step, on its own. Enabling is saving a
/// message, which is how the web infers the note is on.
struct FollowUpSheet: View {
    let projectId: String

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var projectName: String { store.dashboard(for: projectId)?.project.internalName ?? "" }

    @State private var intent: JSONValue?
    @State private var note = FollowUpNote(message: FollowUpNote.defaultMessage, days: 3)
    @State private var loaded: FollowUpNote?
    @State private var loadError: String?
    @State private var validation = FormValidation()
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        FormNotice(style: .error, title: "Couldn't load the project", message: loadError)
                    }
                    FormSegment(title: "Message",
                                description: "Sent automatically to contacted members who haven't responded yet.",
                                hasError: validation.showsAll && !validation.isValid) {
                        MessageEditor(label: nil, text: $note.message, field: FollowUpNote.messageField)
                    }
                    FormSegment(title: "Timing") {
                        DayStepper(days: $note.days, range: FollowUpNote.dayRange)
                    }
                    Label("Identifying details remain hidden until members pursue.", systemImage: "eye.slash")
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textSecondary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
                .disabled(intent == nil)
            }
            // Cards on the canvas, as on the dashboard behind it.
            .background(AxialColor.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Enable Follow-Up")
            .navigationSubtitle(projectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The system's close and confirm roles: the glass ✕, and the
                // tinted ✓ that reads as the sheet's one action.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Label("Enable", systemImage: "checkmark") }
                    }
                    .tint(AxialColor.brandPrimary)
                    .disabled(intent == nil || isSaving)
                    .accessibilityIdentifier("follow-up-enable")
                }
            }
        }
        .environment(validation)
        // Full height: a half sheet left too little room to work in.
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving || (loaded != nil && note != loaded))
        .onChange(of: note, initial: true) { _, note in validation.errors = note.errors }
        .task { await load() }
        .alert("Couldn't enable the follow-up note", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        ), presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func load() async {
        do {
            let intent = try await store.rawProject(id: projectId)
            self.intent = intent
            note = FollowUpNote(intent: intent)
            loaded = note
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        guard let intent else { return }
        validation.revealAll()
        guard validation.isValid else {
            Haptics.error()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.updateProject(id: projectId, patch: note.patch(over: intent))
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            saveError = error.localizedDescription
        }
    }
}

/// How many business days to wait — the web's inline number select, as a
/// stepper beside the value it sets, so the choice reads as a sentence.
private struct DayStepper: View {
    @Binding var days: Int
    let range: ClosedRange<Int>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(days, format: .number)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AxialColor.textPrimary)
                        .contentTransition(.numericText(value: Double(days)))
                    Text("business days")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                }
                Text("after the teaser is first shared")
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textSecondary)
            }
            .animation(reduceMotion ? nil : .snappy, value: days)
            .accessibilityHidden(true)

            Spacer(minLength: 8)

            Stepper("Send after", value: $days, in: range)
                .labelsHidden()
                .accessibilityLabel("Send after")
                .accessibilityValue("\(days) business days after the teaser is first shared")
                .accessibilityIdentifier("follow-up-days")
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// `axl-token-textarea`: the message, with its merge tags as chips, and
/// the one insert button the web has. Shared by the follow-up note and the
/// CIM note.
struct MessageEditor: View {
    let label: String?
    @Binding var text: String
    let field: FormFieldKey
    var minHeight: CGFloat = 140

    @Environment(FormValidation.self) private var validation
    @State private var isFocused = false
    @State private var controller = TokenTextController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormField(label: label, field: field) {
                TokenTextView(text: $text, isFocused: $isFocused, controller: controller,
                              minHeight: minHeight, accessibilityIdentifier: "message-editor")
                    .modifier(InputChrome(isFocused: isFocused,
                                          isInvalid: validation.visibleError(for: field) != nil,
                                          isMultiline: true))
            }
            Button {
                Haptics.selection()
                controller.insert(.recipientFirstName)
            } label: {
                Label("Insert First Name", systemImage: "person.text.rectangle")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .tint(AxialColor.textPrimary)
            .accessibilityHint("Adds the recipient's first name at the cursor")
            .accessibilityIdentifier("insert-first-name")
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { validation.touch(field) }
        }
    }
}
