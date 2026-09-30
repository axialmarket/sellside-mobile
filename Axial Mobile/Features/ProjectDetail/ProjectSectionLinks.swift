//
//  ProjectSectionLinks.swift
//  Axial Mobile
//

import SwiftUI

/// The way into a project's member lists: one card per section, side by side,
/// each showing where that section stands and pushing it when tapped.
///
/// These are the project's numbers *and* its navigation — a count you can't
/// act on is trivia, and a list you can't size up before opening costs a tap
/// to learn nothing. The chevron is there so the card reads as a destination
/// rather than a statistic.
struct ProjectSectionLinks: View {
    let projectId: String
    let sections: [SellsideDeal.Bucket]
    let counts: [SellsideDeal.Bucket: Int]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(sections) { section in
                NavigationLink(value: ProjectsRoute.deals(projectId: projectId, bucket: section)) {
                    card(section)
                }
                .buttonStyle(CardButtonStyle())
                .accessibilityLabel("\(counts[section] ?? 0) \(section.title)")
                .accessibilityHint("Opens the \(section.title.lowercased()) members")
                .accessibilityIdentifier("project-section-\(section.title.lowercased())")
            }
        }
    }

    private func card(_ section: SellsideDeal.Bucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(counts[section] ?? 0)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
            Text(section.title)
                .font(.caption)
                .foregroundStyle(AxialColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
    }
}

/// Placeholder cards, sized like the real ones so nothing shifts on load.
struct ProjectSectionLinksSkeleton: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBox(width: 28, height: 22, cornerRadius: 6)
                    SkeletonBox(width: 70, height: 12, cornerRadius: 6)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
            }
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading project sections")
    }
}

#Preview {
    NavigationStack {
        VStack(spacing: 16) {
            ProjectSectionLinks(
                projectId: "abc",
                sections: SellsideDeal.Bucket.allCases,
                counts: [.recommended: 24, .contacted: 12, .interested: 5]
            )
            ProjectSectionLinks(
                projectId: "abc",
                sections: [.contacted, .interested],
                counts: [.contacted: 0, .interested: 0]
            )
            ProjectSectionLinksSkeleton()
            Spacer()
        }
        .padding(16)
        .background(AxialColor.layer2)
    }
}
