//
//  ProjectCard.swift
//  Axial Mobile
//

import SwiftUI

/// One sellside project as a card: name + status, sectors, the three
/// counts, and a contact/created footer.
struct ProjectCard: View {
    let project: SellsideProject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(project.internalName)
                    .font(.headline)
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                StatusTag(state: project.supplyState)
            }

            if !project.sectors.isEmpty {
                Text(project.sectorNames)
                    .font(.subheadline)
                    .foregroundStyle(AxialColor.textSecondary)
                    .lineLimit(1)
            }

            Divider()

            HStack(alignment: .top, spacing: 0) {
                stat(count: project.activeRecommendations, label: "Recommended",
                     unread: project.unreadRecommendations ?? 0)
                stat(count: project.activeDeals, label: "Contacted")
                stat(count: project.interestedMembers, label: "Interested")
            }

            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AxialColor.border))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func stat(count: Int, label: String, unread: Int = 0) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AxialColor.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(AxialColor.textSecondary)
            if unread > 0 {
                Text("\(unread) new")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AxialColor.brandPrimary, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        let contact = project.assignedToUser?.fullName
        let created = project.createdAt.map {
            "Created \($0.formatted(.relative(presentation: .named)))"
        }
        let parts = [contact, created].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(AxialColor.textPlaceholder)
        }
    }
}

#Preview("States") {
    ScrollView {
        VStack(spacing: 12) {
            ProjectCard(project: .mock())
            ProjectCard(project: .mock(name: "Quiet Deal", state: .draft, recommended: 0,
                                       unread: nil, contacted: 0, interested: 0, sectors: []))
            ProjectCard(project: .mock(
                name: "A Project With A Really Long Internal Name That Wraps",
                state: .reviewingLois, unread: 12))
            ProjectCard(project: .mock(state: .underLoi, unread: nil))
        }
        .padding()
    }
    .background(AxialColor.layer2)
}

#Preview("Redacted") {
    ProjectCard(project: .mock(unread: nil))
        .redacted(reason: .placeholder)
        .padding()
        .background(AxialColor.layer2)
}
