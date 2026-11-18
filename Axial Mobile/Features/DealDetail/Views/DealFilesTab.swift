//
//  DealFilesTab.swift
//  Axial Mobile
//

import SwiftUI

/// The deal's files — the web's Files rows (`DealFilesComponent`): what's
/// been shared with this buyer, and anything attached to a message. Tapping
/// one downloads it and opens it in the system previewer.
struct DealFilesTab: View {
    let files: [DealFile]
    let isLoaded: Bool
    /// The file being downloaded, if any.
    let openingFileId: String?
    let onOpen: (DealFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isLoaded, files.isEmpty {
                DealCardSkeleton(rows: 1)
                    .transition(.opacity)
            } else if files.isEmpty {
                EmptyStateCard(message: "No files have been shared with this member yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        FileRow(file: file, isOpening: openingFileId == file.id) { onOpen(file) }
                            .disabled(openingFileId != nil)
                        if file.id != files.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .cardSurface()
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isLoaded)
    }
}

private struct FileRow: View {
    let file: DealFile
    let isOpening: Bool
    let onTap: () -> Void

    /// "NDA · PDF · Oct 3, 2026".
    private var details: String {
        [file.kind.label, file.format, file.date?.formatted(date: .abbreviated, time: .omitted)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var isLink: Bool {
        if case .link = file.source { return true }
        return false
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: file.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(AxialColor.brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(AxialColor.brandSubtle, in: RoundedRectangle(cornerRadius: AxialRadius.control))
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AxialColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(AxialColor.textSecondary)
                }
                Spacer(minLength: 8)
                // Both always present, so the row doesn't change shape while
                // the download runs.
                ZStack {
                    Image(systemName: isLink ? "arrow.up.right.square" : "arrow.down.circle")
                        .foregroundStyle(AxialColor.textPlaceholder)
                        .opacity(isOpening ? 0 : 1)
                    ProgressView()
                        .opacity(isOpening ? 1 : 0)
                }
                .frame(width: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel("\(file.filename), \(details)")
        .accessibilityHint(isLink ? "Opens the link" : "Downloads and opens the file")
        .accessibilityIdentifier("deal-file-\(file.id)")
    }
}
