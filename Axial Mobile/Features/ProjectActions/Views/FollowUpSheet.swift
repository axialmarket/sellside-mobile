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
                    FormSegment(title: "Follow-Up Note",
                                description: "Automatically send a follow-up note to contacted members after a set number of business days.",
                                hasError: validation.showsAll && !validation.isValid) {
                        MessageEditor(label: "Message", text: $note.message, field: FollowUpNote.messageField)
                        HStack(spacing: 8) {
                            Text("Send")
                            Picker("Days", selection: $note.days) {
                                ForEach(FollowUpNote.dayOptions, id: \.self) { Text(String($0)).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(AxialColor.brandPrimary)
                            Text("business days after initial teaser share")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textPrimary)
                        FormNotice(style: .neutral, message: "Identifying details remain hidden until members pursue.")
                    }
                }
                .padding(16)
                .disabled(intent == nil)
            }
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

/// `axl-token-textarea`: the message with its merge tags as plain
/// `{tokens}`, plus the one insert button the web has.
struct MessageEditor: View {
    let label: String
    @Binding var text: String
    let field: FormFieldKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormTextEditor(label: label, text: $text, field: field, minHeight: 140)
            Button {
                Haptics.selection()
                text = text.isEmpty ? MergeTag.recipientFirstName : text + " " + MergeTag.recipientFirstName
            } label: {
                Label("Add Recipient's First Name", systemImage: "person.crop.circle.badge.plus")
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }
}
