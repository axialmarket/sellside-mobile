//
//  DealComposeSheet.swift
//  Axial Mobile
//

import SwiftUI

/// One text, sent somewhere: a reply, an internal comment, a follow-up.
/// The three differ only in their title, what sits above the text, and the
/// call they make, so they share the sheet.
struct DealComposeSheet<Header: View>: View {
    let title: String
    let subtitle: String
    let sendLabel: String
    let placeholder: String
    var note: String?
    /// Offers the web's insert button for `{recipient[first_name]}` — follow-ups.
    var offersMergeTag = false
    var canSend: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @State var text: String
    @ViewBuilder let header: Header
    let onSend: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isFocused = false
    @State private var controller = TokenTextController()
    @State private var isSending = false
    @State private var sendError: String?
    @State private var isConfirmingDiscard = false
    @State private var initialText: String?

    private var isDirty: Bool { text != (initialText ?? text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    // Shows any merge tag as a chip, in a follow-up or not.
                    TokenTextView(text: $text, isFocused: $isFocused, controller: controller,
                                  minHeight: 176, accessibilityIdentifier: "deal-compose-text")
                        .overlay(alignment: .topLeading) {
                            Text(placeholder)
                                .font(.body)
                                .foregroundStyle(AxialColor.textPlaceholder)
                                .opacity(text.isEmpty ? 1 : 0)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: AxialRadius.well))
                        .overlay(RoundedRectangle(cornerRadius: AxialRadius.well)
                            .strokeBorder(isFocused ? AxialColor.brandPrimary : AxialColor.border))
                    if offersMergeTag {
                        Button {
                            Haptics.selection()
                            controller.insert(.recipientFirstName)
                        } label: {
                            Label("Insert First Name", systemImage: "person.text.rectangle")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .tint(AxialColor.textPrimary)
                    }
                    if let note {
                        FormNotice(style: .neutral, message: note)
                    }
                }
                .padding(16)
                .disabled(isSending)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AxialColor.layer2)
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        if isDirty { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .disabled(isSending)
                    .confirmationDialog("Discard this draft?", isPresented: $isConfirmingDiscard,
                                        titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await send() }
                    } label: {
                        Label(sendLabel, systemImage: "paperplane")
                    }
                    .tint(AxialColor.brandPrimary)
                    .disabled(!canSend(text) || isSending)
                    .accessibilityIdentifier("deal-compose-send")
                }
            }
            .overlay {
                ProgressView().opacity(isSending ? 1 : 0)
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSending || isDirty)
        .onAppear {
            if initialText == nil { initialText = text }
            isFocused = true
        }
        .alert("Couldn't send", isPresented: Binding(
            get: { sendError != nil }, set: { if !$0 { sendError = nil } }
        ), presenting: sendError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await onSend(text.trimmingCharacters(in: .whitespacesAndNewlines))
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            sendError = error.localizedDescription
        }
    }
}

extension DealComposeSheet where Header == EmptyView {
    init(title: String, subtitle: String, sendLabel: String, placeholder: String, note: String? = nil,
         offersMergeTag: Bool = false, text: String = "", onSend: @escaping (String) async throws -> Void) {
        self.init(title: title, subtitle: subtitle, sendLabel: sendLabel, placeholder: placeholder, note: note,
                  offersMergeTag: offersMergeTag, text: text, header: { EmptyView() }, onSend: onSend)
    }
}

/// The To and Subject lines above a reply.
struct MessageHeaderFields: View {
    let to: [DealMessage.Recipient]
    @Binding var subject: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("To")
                    .foregroundStyle(AxialColor.textSecondary)
                    .frame(width: 60, alignment: .leading)
                Text(to.isEmpty ? "No recipient" : to.map(\.displayName).joined(separator: ", "))
                    .foregroundStyle(to.isEmpty ? AxialColor.errorText : AxialColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(12)
            Divider().padding(.leading, 12)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Subject")
                    .foregroundStyle(AxialColor.textSecondary)
                    .frame(width: 60, alignment: .leading)
                TextField("Subject", text: $subject)
                    .foregroundStyle(AxialColor.textPrimary)
            }
            .padding(12)
        }
        .font(.subheadline)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: AxialRadius.well))
        .overlay(RoundedRectangle(cornerRadius: AxialRadius.well).strokeBorder(AxialColor.border))
    }
}
