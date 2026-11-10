//
//  ProjectCard.swift
//  Axial Mobile
//

import SwiftUI

/// One sellside project as a card: name + status, sectors, the three
/// counts, and a contact/created footer.
///
/// Sits on `layer3`, not `layer2`: white on near-white left only a hairline
/// between neighbours. The counts get their own inset strip, so each card
/// reads as header, numbers, footer rather than one run of text.
struct ProjectCard: View {
    let project: SellsideProject

    /// The card's own corner radius, shared with the zoom transition so the
    /// push grows out of the card's actual shape rather than a guessed one.
    static let cornerRadius: CGFloat = 16
    /// Shared with the zoom transition too, so the card doesn't change
    /// weight as the push begins.
    static let shadowOpacity: Double = 0.07
    static let shadowRadius: CGFloat = 6
    static let shadowY: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(project.internalName)
                        .font(.headline)
                        .foregroundStyle(AxialColor.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StatusTag(state: project.supplyState)
                }
                if !project.sectors.isEmpty {
                    Text(project.sectorNames)
                        .font(.subheadline)
                        .foregroundStyle(AxialColor.textSecondary)
                        .lineLimit(1)
                }
            }

            stats

            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(AxialColor.border)
        )
        .shadow(color: .black.opacity(Self.shadowOpacity), radius: Self.shadowRadius, y: Self.shadowY)
    }

    /// The three counts in one inset strip, divided into columns.
    private var stats: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(count: project.activeRecommendations, label: "Recommended",
                 unread: project.unreadRecommendations ?? 0)
            Divider().frame(height: 36)
            stat(count: project.activeDeals, label: "Contacted")
            Divider().frame(height: 36)
            stat(count: project.interestedMembers, label: "Interested")
        }
        .padding(.vertical, 10)
        .background(AxialColor.layer2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AxialColor.border))
    }

    /// Count, label, then any unread count on a line of its own. Unread
    /// used to be a badge beside the number, but in a third of the card a
    /// three-digit count and "349 new" don't both fit, and the count wrapped
    /// a digit per line. Now the number always gets the column's full width.
    private func stat(count: Int, label: String, unread: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count, format: .number)
                .font(.title3.weight(.semibold).monospacedDigit())
                // A zero is the quiet case; let the counts that matter stand out.
                .foregroundStyle(count == 0 ? AxialColor.textPlaceholder : AxialColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(AxialColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if unread > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AxialColor.brandPrimary)
                        .frame(width: 6, height: 6)
                    Text("\(unread.formatted()) new")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AxialColor.brandPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        // Top-aligned, so the columns keep a common baseline when only
        // Recommended carries the extra line.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        let contact = project.assignedToUser?.fullName
        let created = project.createdAt.map {
            "Created \($0.formatted(.relative(presentation: .named)))"
        }
        if contact != nil || created != nil {
            HStack(spacing: 12) {
                if let contact {
                    Label(contact, systemImage: "person")
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let created {
                    Label(created, systemImage: "calendar")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(AxialColor.textSecondary)
            .labelStyle(FooterLabelStyle())
        }
    }
}

/// A small, muted icon ahead of the text, tighter than the system default.
private struct FooterLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .imageScale(.small)
                .foregroundStyle(AxialColor.textPlaceholder)
            configuration.title
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
            ProjectCard(project: .mock(name: "Project Infinity", recommended: 356, unread: 349,
                                       contacted: 1_204, interested: 87))
        }
        .padding()
    }
    .background(AxialColor.layer3)
}

#Preview("Redacted") {
    ProjectCard(project: .mock(unread: nil))
        .redacted(reason: .placeholder)
        .padding()
        .background(AxialColor.layer3)
}
