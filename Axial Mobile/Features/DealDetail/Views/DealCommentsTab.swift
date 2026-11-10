//
//  DealCommentsTab.swift
//  Axial Mobile
//

import SwiftUI

/// The sidebar's Comments tab — `axl-deal-notes`: the team's internal
/// comments on this deal, newest last, with your own deletable.
struct DealCommentsTab: View {
    let notes: [DealNote]
    let isLoaded: Bool
    let error: String?
    let isOwn: (DealNote) -> Bool
    let onAdd: () -> Void
    let onDelete: (DealNote) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isLoaded, notes.isEmpty {
                DealCardSkeleton(rows: 1)
            } else if let error, notes.isEmpty {
                DealTabError(title: "Couldn't load comments", message: error, onRetry: onRetry)
            } else if notes.isEmpty {
                EmptyStateCard(message: "No comments have been added yet.")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(notes) { note in
                        CommentCard(note: note, canDelete: isOwn(note)) { onDelete(note) }
                    }
                }
            }

            Button(action: onAdd) {
                Label("Add Internal Comment", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(AxialColor.textPrimary)
            .controlSize(.large)
            .accessibilityIdentifier("deal-add-comment")

            Text("Comments are only visible to your team.")
                .font(.caption)
                .foregroundStyle(AxialColor.textPlaceholder)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct CommentCard: View {
    let note: DealNote
    let canDelete: Bool
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PersonAvatar(name: note.authorName, url: nil, size: 26)
                Text(note.authorName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                Spacer(minLength: 4)
                Text(note.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(AxialColor.textPlaceholder)
                Menu {
                    Button("Delete Comment", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(AxialColor.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .opacity(canDelete ? 1 : 0)
                .disabled(!canDelete)
                .accessibilityHidden(!canDelete)
                .confirmationDialog("Delete this comment?", isPresented: $isConfirmingDelete,
                                    titleVisibility: .visible) {
                    Button("Delete Comment", role: .destructive, action: onDelete)
                }
            }
            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(AxialColor.textPrimary)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
    }
}
