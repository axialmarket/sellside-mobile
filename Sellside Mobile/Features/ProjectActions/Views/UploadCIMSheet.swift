//
//  UploadCIMSheet.swift
//  Sellside Mobile
//

import SwiftUI

/// Resolves "Upload your CIM": the Upload Documentation segment of the web's
/// CIM / Summary Materials step, on its own — files or a link, and how
/// they're shared once a member signs the NDA.
///
/// Files upload one by one before the project is saved, so a failure part
/// way leaves the rest picked and ready to try again.
struct UploadCIMSheet: View {
    let projectId: String

    @Environment(ProjectDashboardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var projectName: String { store.dashboard(for: projectId)?.project.internalName ?? "" }

    @State private var intent: JSONValue?
    @State private var loadError: String?
    @State private var files: [PickedFile] = []
    /// Already on the server from an attempt that failed at the save.
    @State private var uploadedCount = 0
    @State private var didSave = false
    @State private var upload = CIMUpload()
    @State private var validation = FormValidation()
    @State private var isPicking = false
    @State private var pickError: String?
    @State private var progress: String?
    @State private var saveError: String?

    private typealias F = CIMUpload.Field

    private var ndaIsSignable: Bool { intent.map(CIMUpload.ndaIsSignable(intent:)) ?? false }
    private var hasMaterials: Bool { !files.isEmpty || uploadedCount > 0 || !upload.linkedURL.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadError {
                        FormNotice(style: .error, title: "Couldn't load the project", message: loadError)
                    }
                    materials
                    if hasMaterials {
                        sharing
                            .transition(.opacity)
                    }
                }
                .padding(16)
                .animation(.easeOut(duration: 0.2), value: hasMaterials)
                .disabled(intent == nil || progress != nil)
            }
            .navigationTitle("Upload CIM")
            .navigationSubtitle(projectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .disabled(progress != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        Task { await save() }
                    } label: {
                        if progress != nil { ProgressView() } else { Label("Upload", systemImage: "checkmark") }
                    }
                    .tint(AxialColor.brandPrimary)
                    .disabled(intent == nil || progress != nil)
                    .accessibilityIdentifier("upload-cim-save")
                }
                // Adding files is the sheet's main gesture, so it lives in
                // the bar, within reach, as well as in the drop zone.
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        isPicking = true
                    } label: {
                        Label("Add Files", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                    }
                    .disabled(intent == nil || progress != nil || !upload.linkedURL.isEmpty
                              || files.count + uploadedCount >= CIMUpload.maxFiles)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let progress {
                    Label(progress, systemImage: "arrow.up.circle")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: Capsule())
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: progress)
        }
        .environment(validation)
        // Full height: a half sheet left too little room to work in.
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasMaterials || progress != nil)
        .onChange(of: upload, initial: true) { revalidate() }
        .onChange(of: files.count) { revalidate() }
        .task { await load() }
        .onDisappear { refreshIfPartlyUploaded() }
        .fileImporter(isPresented: $isPicking,
                      allowedContentTypes: PickedFile.contentTypes(for: DocumentRules.cimExtensions),
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            add(urls.compactMap(PickedFile.read))
        }
        .alert("Couldn't add those files", isPresented: Binding(
            get: { pickError != nil }, set: { if !$0 { pickError = nil } }
        ), presenting: pickError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .alert("Couldn't upload the CIM", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        ), presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: Sections

    private var materials: some View {
        FormSegment(title: "Upload Documentation", isRequired: true,
                    description: "Upload your CIM, summary materials, process letter, etc. All .pdf files are watermarked.",
                    hasError: validation.showsAll && (validation.errors[F.materials] != nil || validation.errors[F.link] != nil)) {
            FormField(label: nil, field: F.materials) {
                VStack(alignment: .leading, spacing: 10) {
                    if upload.linkedURL.isEmpty {
                        UploadZone(title: "Choose files to upload", detail: "PDF, DOCX, PPTX, XLSX, or CSV (max. 50 MB)",
                                   isInvalid: validation.visibleError(for: F.materials) != nil) { isPicking = true }
                    }
                    if uploadedCount > 0 {
                        Label("\(uploadedCount) uploaded", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AxialColor.success)
                    }
                    ForEach(files) { file in
                        PickedFileRow(file: file) { files.removeAll { $0.id == file.id } }
                    }
                    if !upload.linkedURL.isEmpty {
                        LinkRow(url: upload.linkedURL) { upload.linkedURL = "" }
                    } else if files.isEmpty, let intent, CIMUpload.canLink(intent: intent) {
                        LinkEntry(divider: "or link your documents", placeholder: "https://example.com/cim-documents",
                                  confirmed: upload.linkedURL,
                                  isInvalid: validation.visibleError(for: F.link) != nil) { url in
                            validation.touch(F.link)
                            // An invalid link isn't kept — as on the web.
                            if URLRule.isValid(url) { upload.linkedURL = url }
                        }
                    }
                }
            }
        }
    }

    private var sharing: some View {
        FormSegment(title: "Sharing Method", isRequired: true,
                    description: "How would you like to share your CIM materials with buyers?",
                    hasError: validation.showsAll && validation.errors[F.sharing] != nil) {
            FormRadioGroup(label: nil, choices: [
                .init(value: "enabled", label: "Automatic CIM Share",
                      detail: "CIM materials shared automatically after NDA is executed", systemImage: "bolt.badge.checkmark"),
                .init(value: "off", label: "Manual CIM Share",
                      detail: "Grant access to CIM materials manually for each member", systemImage: "checklist"),
            ], selection: $upload.sharing, field: F.sharing)
            // The signable-NDA rule shows as soon as it's broken; the
            // missing choice waits for Upload.
            if upload.sharing == "enabled", !ndaIsSignable {
                FormNotice(style: .error,
                           message: "To use Automatic CIM Share, please select an electronically signable NDA.")
            }
        }
    }

    // MARK: Actions

    private func revalidate() {
        validation.errors = upload.errors(fileCount: files.count + uploadedCount, ndaIsSignable: ndaIsSignable)
    }

    /// The upload component's checks: ten files at most, accepted types,
    /// 50 MB each (plus the silent 2 MB tolerance).
    private func add(_ picked: [PickedFile]) {
        var picked = picked
        // Files already uploaded on a failed attempt count against the ten.
        let room = CIMUpload.maxFiles - files.count - uploadedCount
        if picked.count > room {
            pickError = "You can upload up to 10 documents."
            picked = Array(picked.prefix(max(room, 0)))
        }
        if let error = PickedFile.rejection(for: picked, extensions: DocumentRules.cimExtensions,
                                            maxMB: DocumentRules.cimMaxMB, toleranceMB: DocumentRules.cimToleranceMB,
                                            typeList: "PDF, DOCX, PPTX, XLSX, CSV") {
            pickError = error
            return
        }
        files.append(contentsOf: picked)
        validation.touch(F.materials)
    }

    private func load() async {
        do {
            intent = try await store.rawProject(id: projectId)
            revalidate()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        validation.revealAll()
        revalidate()
        guard validation.isValid else {
            Haptics.error()
            return
        }
        defer { progress = nil }
        do {
            let total = files.count
            while let file = files.first {
                progress = "Uploading \(total - files.count + 1) of \(total)…"
                try await store.uploadDocument(to: projectId, file: file, bucket: "OM")
                files.removeFirst()
                uploadedCount += 1
            }
            progress = "Saving…"
            try await store.updateProject(id: projectId, patch: upload.patch)
            didSave = true
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            saveError = error.localizedDescription
        }
    }

    /// Files reached the server even if the save after them failed, so the
    /// dashboard refetches when the sheet goes away — otherwise it keeps
    /// asking for a CIM that's already there and hides Send CIM.
    private func refreshIfPartlyUploaded() {
        guard uploadedCount > 0, !didSave else { return }
        Task { await store.load(id: projectId) }
    }
}
