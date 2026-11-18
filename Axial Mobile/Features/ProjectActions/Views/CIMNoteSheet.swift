//
//  CIMNoteSheet.swift
//  Axial Mobile
//

import SwiftUI

/// "Draft CIM Note" — cim-note-sidebar.component.html: who gets it, who's
/// CC'd, the message, and the files it carries. One recipient or many, it's
/// the same sheet and the same `POST /deals/send-cim`.
struct CIMNoteSheet: View {
    let projectId: String
    let deals: [SellsideDeal]
    let onSent: (String) -> Void

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var intent: JSONValue?
    @State private var members: [AccountMember] = []
    @State private var ccMembers: [String] = []
    @State private var message = CIMNoteRecipients.defaultMessage
    @State private var validation = FormValidation()
    @State private var isPickingCc = false
    @State private var isSending = false
    @State private var sendError: String?
    /// The project couldn't be fetched, so there's no saved note to start
    /// from and nothing to send yet.
    @State private var loadError: String?

    private var recipients: CIMNoteRecipients { CIMNoteRecipients(deals: deals) }
    private static let messageField: FormFieldKey = "cimNote.message"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        FormNotice(style: .error, title: "Couldn't load the project", message: loadError)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("cim-note-retry")
                    }
                    if let notice = recipients.inquiriesNotice {
                        FormNotice(style: .warning, message: notice)
                    }
                    if let notice = recipients.ineligibleNotice {
                        FormNotice(style: .warning, message: notice)
                    }
                    FormSegment(title: nil) {
                        recipientList
                        ccRow
                        MessageEditor(label: "Message", text: $message, field: Self.messageField)
                        files
                    }
                }
                .padding(16)
                .disabled(isSending)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Draft CIM Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending { ProgressView() } else { Text(recipients.ctaLabel).font(.subheadline.weight(.semibold)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AxialColor.brandPrimary)
                    .disabled(recipients.eligible.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || isSending || intent == nil)
                    .accessibilityIdentifier("cim-note-send")
                }
            }
        }
        .environment(validation)
        // Full height: a half sheet left too little room to work in.
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSending)
        .onChange(of: message, initial: true) { _, message in
            validation.errors = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [Self.messageField: "Required"] : [:]
        }
        .task { await load() }
        .sheet(isPresented: $isPickingCc) {
            FormMultiPicker(title: "CC", choices: members.map { .init(value: $0.id, label: $0.fullName) },
                            selection: $ccMembers, searchable: members.count > 8)
        }
        .alert("CIM Not Sent", isPresented: Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } }),
               presenting: sendError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: Sections

    private var recipientList: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormFieldLabel(text: "Recipient(s)")
            FlowLayout(spacing: 6) {
                ForEach(recipients.eligible) { deal in
                    TagCapsule(text: deal.demandUserName ?? deal.displayName, palette: .blue)
                }
            }
            if recipients.eligible.isEmpty {
                Text("No eligible members.")
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
        }
    }

    private var ccRow: some View {
        let names = ccMembers.compactMap { id in members.first { $0.id == id }?.fullName }
        return FormPickerRow(label: "CC", field: "cimNote.cc", summary: names, placeholder: "Select a team member") {
            isPickingCc = true
        }
        .disabled(members.isEmpty)
    }

    @ViewBuilder
    private var files: some View {
        let files = intent.map(CIMNoteRecipients.files(from:)) ?? []
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                FormFieldLabel(text: "Files")
                ForEach(files, id: \.self) { file in
                    Label(file, systemImage: file.hasPrefix("http") ? "link" : "doc.text")
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: Data

    private func load() async {
        let intent: JSONValue
        do {
            intent = try await store.rawProject(id: projectId)
            loadError = nil
        } catch {
            // Without this the Send button stayed disabled with no reason.
            loadError = error.localizedDescription
            return
        }
        self.intent = intent
        message = CIMNoteRecipients.message(from: intent)
        ccMembers = intent["cim"]?["cc_members"]?.strings ?? []
        members = await store.accountMembers(for: intent)
    }

    private func send() async {
        guard let intent else { return }
        isSending = true
        defer { isSending = false }
        let eligible = recipients.eligible
        do {
            try await store.sendCim(SendCIMRequest(message: message, ccMembers: ccMembers,
                                                   dealIds: eligible.map(\.id),
                                                   subject: intent["headline"]?.string ?? ""),
                                    on: projectId)
            Haptics.success()
            onSent(CIMNoteRecipients.success(eligible))
            dismiss()
        } catch APIError.server(409, _, _) {
            // The whole batch rolled back.
            Haptics.error()
            sendError = "Some selected members aren't eligible for the CIM, so nothing was sent. Refreshing your member list — review the selection and try again."
            Task { await store.load(id: projectId) }
        } catch {
            Haptics.error()
            sendError = "Could not send CIM."
        }
    }
}
