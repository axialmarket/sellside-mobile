//
//  DocumentStepViews.swift
//  Axial Mobile
//

import SwiftUI

// MARK: - Custom Teaser

/// Custom Teaser — custom-teaser-step.component.html. Documents only; no
/// form controls.
struct CustomTeaserStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isPicking = false
    @State private var pendingDelete: SetupDocument?
    @State private var uploadError: String?

    var body: some View {
        SetupSegment(title: "Teaser",
                     description: "Upload your custom teaser. Custom Teasers are shared with members after they pursue your deal.") {
            if let teaser = session.form.documents.teaser {
                DocumentRow(document: teaser) { pendingDelete = teaser }
            } else {
                UploadZone(title: "Choose a file to upload", detail: "Supported files") { isPicking = true }
                Link("Supported files",
                     destination: URL(string: "https://guide.axial.net/articles/list-of-supported-file-types/")!)
                    .font(.footnote)
            }
        }
        .fileImporter(isPresented: $isPicking,
                      allowedContentTypes: PickedFile.contentTypes(for: DocumentRules.teaserExtensions)) { result in
            guard case .success(let url) = result, let file = PickedFile.read(url) else { return }
            if let error = PickedFile.rejection(for: [file], extensions: DocumentRules.teaserExtensions, maxMB: 3001) {
                uploadError = error
                return
            }
            if let existing = session.form.documents.teaser { session.form.documents.remove(existing) }
            session.form.documents.add(bucket: "T", filename: file.filename, mimeType: file.mimeType, data: file.data)
        }
        .modifier(DeleteDocumentConfirmation(pending: $pendingDelete, isShared: session.context.isShared) {
            session.form.documents.remove($0)
        })
        .alert("Couldn't add that file", isPresented: errorBinding, presenting: uploadError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { uploadError != nil }, set: { if !$0 { uploadError = nil } })
    }
}

// MARK: - NDA

/// NDA — nda-step.component.html: Axial Standard, Custom (upload or link),
/// or none.
struct NDAStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isPicking = false
    @State private var pickedForSignature: PickedFile?
    @State private var pendingDelete: SetupDocument?
    @State private var isConfirmingWaive = false
    @State private var uploadError: String?
    private typealias F = NDAForm.Field

    private var extensions: [String] {
        session.context.account.requireEditableNDA ? ["docx"] : DocumentRules.ndaExtensions
    }

    var body: some View {
        let form = session.form
        let context = session.context
        let canWaive = context.account.canWaiveNDA || session.intent["nda_type"]?.string == "waive"
        let canLink = session.intent["nda_type"]?.string == "linked" || session.intent["linked_nda"]?.text != nil
            || context.account.canLinkNDA
        let missingCustom = form.nda.ndaType == "custom" && !form.nda.hasCustomNDA(form.documents)

        SetupSegment(title: "Choose An Agreement", isRequired: true,
                     description: "Select the NDA you would like to use for this deal:",
                     hasError: session.segmentHasError([F.ndaType, F.linkedNdaUrl])) {
            SetupField(label: nil, field: F.ndaType) {
                VStack(spacing: 10) {
                    option(value: "axial", title: "Axial Standard NDA", tag: "Recommended",
                           detail: "Electronically signed over 100,000 times by Axial Members", systemImage: "checkmark.seal")
                    option(value: "custom", title: "Custom NDA", detail: "Add your own NDA for members to sign",
                           systemImage: "doc.text")
                    if form.nda.ndaType == "custom" {
                        customNDA(canLink: canLink, isInvalid: missingCustom && session.visibleError(for: F.ndaType) != nil)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if canWaive {
                        option(value: "waive", title: "No NDA", detail: "I will forgo using an NDA for this deal",
                               systemImage: "xmark.circle")
                    }
                }
            }
            if !context.account.canWaiveNDA, session.intent["nda_type"]?.string == "waive" {
                SetupNotice(style: .warning,
                            message: "Warning: The option to forgo using an NDA will be unavailable upon changing your selection.")
            }
        }
        .animation(.easeOut(duration: 0.2), value: form.nda.ndaType)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: PickedFile.contentTypes(for: extensions)) { result in
            guard case .success(let url) = result, let file = PickedFile.read(url) else { return }
            let typeList = extensions.map { $0.uppercased() }.joined(separator: ", ")
            if let error = PickedFile.rejection(for: [file], extensions: extensions, maxMB: DocumentRules.ndaMaxMB,
                                                typeList: typeList) {
                uploadError = error
                return
            }
            // PDFs and Word files can be signed; anything else downloads.
            if ["pdf", "doc", "docx"].contains(file.fileExtension) {
                pickedForSignature = file
            } else {
                session.form.attachNDA(filename: file.filename, mimeType: file.mimeType, data: file.data,
                                       signatureType: "download_only")
            }
            session.touch(F.ndaType)
        }
        .sheet(item: Binding(get: { pickedForSignature.map(IdentifiedFile.init) },
                             set: { if $0 == nil { pickedForSignature = nil } })) { item in
            SignatureSettingsSheet { signatureType in
                session.form.attachNDA(filename: item.file.filename, mimeType: item.file.mimeType,
                                       data: item.file.data, signatureType: signatureType)
            }
        }
        .modifier(DeleteDocumentConfirmation(pending: $pendingDelete, isShared: session.context.isShared) {
            session.form.documents.remove($0)
            session.touch(F.ndaType)
        })
        .confirmationDialog("Delete Document?", isPresented: $isConfirmingWaive, titleVisibility: .visible) {
            Button("Yes, I'm sure", role: .destructive) { select("waive") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DocumentRules.deleteMessage(plural: false, isShared: session.context.isShared,
                                             signable: session.form.documents.customNDA?.isSignable ?? false))
        }
        .alert("Couldn't add that file", isPresented: errorBinding, presenting: uploadError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func option(value: String, title: String, tag: String? = nil, detail: String, systemImage: String) -> some View {
        let isSelected = session.form.nda.ndaType == value
        return Button {
            Haptics.selection()
            if value == "waive", session.form.documents.customNDA != nil {
                isConfirmingWaive = true
            } else {
                select(value)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AxialColor.textPrimary)
                        if let tag { TagCapsule(text: tag, palette: .green) }
                    }
                    Text(detail).font(.footnote).foregroundStyle(AxialColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(isSelected ? AxialColor.brandSubtle : AxialColor.layer1, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? AxialColor.brandPrimary : AxialColor.border, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ value: String) {
        session.form.setNDAType(value)
        session.touch(F.ndaType)
    }

    @ViewBuilder
    private func customNDA(canLink: Bool, isInvalid: Bool) -> some View {
        let form = session.form
        VStack(alignment: .leading, spacing: 10) {
            if let custom = form.documents.customNDA {
                DocumentRow(document: custom) { pendingDelete = custom }
            } else if !form.nda.linkedNdaUrl.isEmpty {
                LinkRow(url: form.nda.linkedNdaUrl) {
                    session.form.linkNDA("")
                    session.touch(F.ndaType)
                }
            } else {
                if session.context.account.requireEditableNDA {
                    SetupNotice(style: .info,
                                message: "Please upload your NDA as a Word file (.docx) so buyside members can redline if needed.")
                }
                UploadZone(title: "Choose a file to upload",
                           detail: "\(extensions.map { $0.uppercased() }.formatted(.list(type: .or))) (max. \(DocumentRules.ndaMaxMB) MB)",
                           isInvalid: isInvalid) { isPicking = true }
                if canLink {
                    LinkEntry(divider: "or link your NDA", placeholder: "https://example.com/nda.pdf",
                              confirmed: form.nda.linkedNdaUrl,
                              isInvalid: session.visibleError(for: F.linkedNdaUrl) != nil) { url in
                        session.form.linkNDA(url)
                        session.touch(F.linkedNdaUrl)
                        session.touch(F.ndaType)
                    }
                }
            }
        }
        .padding(12)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isInvalid ? AxialColor.error : AxialColor.border, lineWidth: isInvalid ? 2 : 1))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { uploadError != nil }, set: { if !$0 { uploadError = nil } })
    }
}

private struct IdentifiedFile: Identifiable {
    let file: PickedFile
    var id: String { file.filename }
}

/// "Signature Settings" — how a custom NDA gets signed. Placing custom
/// e-signature fields happens in an embedded HelloSign editor on the web,
/// which mobile can't host, so that option uploads for setup there.
struct SignatureSettingsSheet: View {
    let onContinue: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice = "basic"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Interested recipients will be able to electronically sign this NDA.")
                    Text("How would you like to place signature fields?")
                        .font(.subheadline.weight(.semibold))
                }
                Section {
                    Picker("Signature fields", selection: $choice) {
                        Text("Add a signature page to the end of my document").tag("basic")
                        Text("Set up my NDA for e-signature (add custom fields)").tag("custom")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    if choice == "custom" {
                        Text("Custom signature fields are placed on the web. The file uploads now; finish placing fields from Project Setup on desktop.")
                    }
                }
            }
            .navigationTitle("Signature Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onContinue(choice)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - CIM / Summary Materials

/// CIM / Summary Materials — cim-upload-documentation and cim-note-template.
struct CIMStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    @State private var isPicking = false
    @State private var pendingDelete: SetupDocument?
    @State private var isConfirmingWaive = false
    @State private var uploadError: String?
    @State private var isPickingCc = false
    private typealias F = CIMForm.Field

    var body: some View {
        @Bindable var session = session
        let form = session.form
        let context = session.context
        let canLink = session.intent["cim_type"]?.string == "linked" || session.intent["linked_cim"]?.text != nil
            || context.account.canLinkCIM
        let canWaive = context.account.canWaiveCIM || session.intent["cim_type"]?.string == "waive"

        SetupSegment(title: "Upload Documentation", isRequired: true,
                     description: "Upload your CIM, summary materials, process letter, etc. All .pdf files are watermarked.",
                     hasError: session.segmentHasError([F.cimType, F.linkedCimUrl, F.smartshareState, F.group])) {
            SetupField(label: nil, field: F.cimType) {
                VStack(alignment: .leading, spacing: 10) {
                    if form.cim.linkedCimUrl.isEmpty {
                        UploadZone(title: "Choose files to upload", detail: "PDF, DOCX, PPTX, XLSX, or CSV (max. 50 MB)",
                                   isInvalid: session.visibleError(for: F.cimType) != nil) { isPicking = true }
                    }
                    ForEach(form.documents.cimDocuments) { document in
                        DocumentRow(document: document) { pendingDelete = document }
                    }
                    if !form.cim.linkedCimUrl.isEmpty, canLink {
                        LinkRow(url: form.cim.linkedCimUrl) {
                            session.form.linkCIM("")
                            session.touch(F.cimType)
                        }
                    }
                    if canLink, form.cim.linkedCimUrl.isEmpty, form.documents.cimDocuments.isEmpty {
                        LinkEntry(divider: "or link your documents", placeholder: "https://example.com/cim-documents",
                                  confirmed: form.cim.linkedCimUrl,
                                  isInvalid: session.visibleError(for: F.linkedCimUrl) != nil) { url in
                            // An invalid link isn't kept — the control reverts.
                            guard URLRule.isValid(url) else {
                                session.touch(F.linkedCimUrl)
                                return
                            }
                            session.form.linkCIM(url)
                            session.touch(F.cimType)
                        }
                    }
                }
            }
            Link("watermarked", destination: URL(string: "https://guide.axial.net/docs/how-to-best-market-deals-on-axial#documents")!)
                .font(.footnote)

            if form.cim.hasMaterials(form.documents) {
                sharingMethod
                    .transition(.opacity)
            }

            if canWaive {
                Button {
                    Haptics.selection()
                    if form.cim.cimType == "waive" {
                        session.form.setCIMWaived(false)
                    } else if !form.documents.cimDocuments.isEmpty {
                        isConfirmingWaive = true
                    } else {
                        session.form.setCIMWaived(true)
                    }
                    session.touch(F.cimType)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: form.cim.cimType == "waive" ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(form.cim.cimType == "waive" ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                        Text("I am preparing the CIM and will upload it once finalized")
                            .font(.subheadline)
                            .foregroundStyle(AxialColor.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
                if !context.account.canWaiveCIM, session.intent["cim_type"]?.string == "waive" {
                    SetupNotice(style: .warning,
                                message: "Warning: The option to forgo using a CIM will be unavailable upon changing your selection.")
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: form.cim.hasMaterials(form.documents))
        .fileImporter(isPresented: $isPicking, allowedContentTypes: PickedFile.contentTypes(for: DocumentRules.cimExtensions),
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            var files = urls.compactMap(PickedFile.read)
            let room = SetupDocuments.maxCIMFiles - session.form.documents.cimDocuments.count
            if files.count > room {
                uploadError = "You can upload up to 10 documents."
                files = Array(files.prefix(max(room, 0)))
            }
            if let error = PickedFile.rejection(for: files, extensions: DocumentRules.cimExtensions,
                                                maxMB: DocumentRules.cimMaxMB, toleranceMB: DocumentRules.cimToleranceMB,
                                                typeList: "PDF, DOCX, PPTX, XLSX, CSV") {
                uploadError = error
                return
            }
            for file in files {
                session.form.attachCIM(filename: file.filename, mimeType: file.mimeType, data: file.data)
            }
            session.touch(F.cimType)
        }
        .modifier(DeleteDocumentConfirmation(pending: $pendingDelete, isShared: context.isShared) {
            session.form.removeCIMDocument($0)
        })
        .confirmationDialog("Delete Documents?", isPresented: $isConfirmingWaive, titleVisibility: .visible) {
            Button("Yes, I'm sure", role: .destructive) { session.form.setCIMWaived(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DocumentRules.deleteMessage(plural: true, isShared: context.isShared, signable: false,
                                             reason: "Selecting this option will remove any attached CIM and summary material documents."))
        }
        .alert("Couldn't add those files", isPresented: errorBinding, presenting: uploadError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }

        noteTemplate($session.form.cim)
    }

    private var sharingMethod: some View {
        let state = Binding<String?>(get: { session.form.cim.smartshareState },
                                     set: { session.form.setCIMSmartshare($0) })
        let groupError = session.validation.errors[F.group]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("Sharing Method").font(.subheadline.weight(.semibold))
                RequiredMarker(isAttention: session.visibleError(for: F.smartshareState) != nil)
            }
            Text("How would you like to share your CIM materials with buyers?")
                .font(.footnote)
                .foregroundStyle(AxialColor.textSecondary)
            SetupRadioGroup(label: nil, choices: [
                .init(value: "enabled", label: "Automatic CIM Share",
                      detail: "CIM materials shared automatically after NDA is executed", systemImage: "bolt.badge.checkmark"),
                .init(value: "off", label: "Manual CIM Share",
                      detail: "Grant access to CIM materials manually for each member", systemImage: "checklist"),
            ], selection: state, field: F.smartshareState)
            if let groupError, !groupError.isEmpty,
               session.showsValidationErrors || session.touched.contains(F.smartshareState) || groupError.contains("signable") {
                SetupNotice(style: groupError.contains("signable") ? .error : .warning, message: groupError)
            }
        }
        .id(F.group)
    }

    private func noteTemplate(_ cim: Binding<CIMForm>) -> some View {
        SetupSegment(title: "CIM Note Template",
                     description: "Personalize the note that goes out with the CIM and summary materials. All information is strictly confidential and shared only with members you grant CIM access to per Axial's privacy policy.") {
            MemberPickerRow(label: "Cc:", helper: "Select team members to be copied on all outbound CIM notes.",
                            placeholder: "- Select a team member -", selection: cim.ccMembers,
                            field: "cim.cimCcMembers")
            MessageEditor(label: "Message:", text: cim.message, field: "cim.cimMessage")
            SetupNotice(style: .neutral, message: "Tip: Add deadlines and additional information to ensure a prompt response.")
            SetupTextField(label: "Schedule a Meeting", text: cim.calendarLink, field: F.calendarLink, placeholder: "https://",
                           helper: "By providing your calendar link, it will be shared with members when you share your CIM.",
                           keyboard: .URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Link("privacy policy", destination: URL(string: "https://www.axial.net/legal/privacy/")!)
                .font(.footnote)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { uploadError != nil }, set: { if !$0 { uploadError = nil } })
    }
}
