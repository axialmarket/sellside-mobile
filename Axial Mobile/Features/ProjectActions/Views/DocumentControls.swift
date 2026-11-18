//
//  DocumentControls.swift
//  Axial Mobile
//

import SwiftUI
import UniformTypeIdentifiers

/// A file the member picked, read out of its security scope.
struct PickedFile: Identifiable {
    let id = UUID()
    let filename: String
    let data: Data
    var mimeType: String { DocumentRules.mimeType(for: filename) }
    var fileExtension: String { (filename as NSString).pathExtension.lowercased() }

    static func read(_ url: URL) -> PickedFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return PickedFile(filename: url.lastPathComponent, data: data)
    }

    /// The upload component's checks, with the web's growl copy.
    static func rejection(for files: [PickedFile], extensions: [String], maxMB: Int, toleranceMB: Int = 0,
                          typeList: String? = nil) -> String? {
        let wrongType = files.filter { !extensions.contains($0.fileExtension) }
        if !wrongType.isEmpty {
            if let typeList {
                return "The following files are not an accepted file type (\(typeList)): \(wrongType.map(\.filename).joined(separator: ", "))"
            }
            return "\(wrongType[0].filename) is not an accepted file type."
        }
        let limit = (maxMB + toleranceMB) * 1_000_000
        let tooBig = files.filter { $0.data.count > limit }
        if !tooBig.isEmpty {
            return "The following files exceed the maximum size of \(maxMB) MB: \(tooBig.map(\.filename).joined(separator: ", "))"
        }
        return nil
    }

    static func contentTypes(for extensions: [String]) -> [UTType] {
        extensions.compactMap { UTType(filenameExtension: $0) }
    }
}

/// The drop zone, as a tappable card: "Click to upload" becomes Choose File.
struct UploadZone: View {
    let title: String
    let detail: String
    var isInvalid = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.up.doc")
                    .font(.title2)
                    .foregroundStyle(AxialColor.brandPrimary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.brandPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AxialColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(AxialColor.layer2, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isInvalid ? AxialColor.error : AxialColor.border,
                                  style: StrokeStyle(lineWidth: isInvalid ? 2 : 1, dash: [6, 4]))
            }
        }
        .buttonStyle(.plain)
    }
}

/// `axl-document-toolbar` for a file picked but not yet uploaded: icon,
/// name, size, and remove.
struct PickedFileRow: View {
    let file: PickedFile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(AxialColor.brandPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Int64(file.data.count).formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(AxialColor.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(file.filename)")
        }
        .padding(12)
        .background(AxialColor.layer2, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A confirmed link, shown like a document.
struct LinkRow: View {
    let url: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(AxialColor.brandPrimary)
            if let destination = URL(string: url) {
                Link(url, destination: destination)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(url).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove link")
        }
        .padding(12)
        .background(AxialColor.layer2, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// "or link your …": a URL draft and Confirm. Typing never touches the
/// form — only Confirm does.
struct LinkEntry: View {
    let divider: String
    let placeholder: String
    let confirmed: String
    let isInvalid: Bool
    let onConfirm: (String) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack { Divider() }
                Text(divider).font(.caption).foregroundStyle(AxialColor.textSecondary).fixedSize()
                VStack { Divider() }
            }
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(confirm)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isInvalid ? AxialColor.error : AxialColor.border, lineWidth: isInvalid ? 2 : 1))
                Button("Confirm", action: confirm)
                    .buttonStyle(.glass)
                    .disabled(draft.trimmingCharacters(in: .whitespaces) == confirmed)
            }
            if isInvalid {
                FormFieldError(message: "Invalid URL")
            }
        }
        .onAppear { draft = confirmed }
    }

    private func confirm() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        let url = trimmed.isEmpty ? "" : URLRule.sanitized(trimmed)
        draft = url
        onConfirm(url)
    }
}
