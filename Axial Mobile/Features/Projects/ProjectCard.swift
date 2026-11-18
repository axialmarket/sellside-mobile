//
//  ProjectCard.swift
//  Axial Mobile
//

import SwiftUI

/// One sellside project as a card: name + status, sectors, the three
/// counts, and a contact/created footer.
///
/// A `cardSurface` on the canvas. The counts get their own inset strip, so
/// each card reads as header, numbers, footer rather than one run of text.
struct ProjectCard: View {
    let project: SellsideProject
    /// A status change is running for this project — from the card's context
    /// menu or swipe action. The tag gives way to a spinner in place.
    var isUpdating = false

    /// The card's own corner radius, shared with the zoom transition so the
    /// push grows out of the card's actual shape rather than a guessed one.
    static let cornerRadius = AxialRadius.card

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(project.internalName)
                        .font(.headline)
                        .foregroundStyle(AxialColor.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Both always present, so the header keeps its shape
                    // while the change runs.
                    StatusTag(state: project.supplyState)
                        .opacity(isUpdating ? 0 : 1)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                                .opacity(isUpdating ? 1 : 0)
                        }
                        .animation(.easeOut(duration: 0.15), value: isUpdating)
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
        .cardSurface(cornerRadius: Self.cornerRadius)
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
        .insetWell()
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
                // Always full size, so a four-digit count reads at the same
                // weight as its neighbours. A third of the card fits seven
                // characters at this size ("100,000+"), so it doesn't need
                // to shrink.
                .fixedSize()
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
                        .fixedSize()
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
    .background(AxialColor.canvas)
}

#Preview("Redacted") {
    ProjectCard(project: .mock(unread: nil))
        .redacted(reason: .placeholder)
        .padding()
        .background(AxialColor.canvas)
}
