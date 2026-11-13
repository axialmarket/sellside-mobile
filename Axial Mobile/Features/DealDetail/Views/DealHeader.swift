//
//  DealHeader.swift
//  Axial Mobile
//

import SwiftUI

/// The top of a deal: who the buyer is and where the deal stands.
///
/// Mirrors `axl-sell-sidebar-header` — "{member} at {account}", then account
/// type • location • years on Axial, then the attribute badges — and adds
/// the status line from the member card, because the sidebar sits beside
/// the grid's status column and a phone screen doesn't.
///
/// Everything here comes from the list row, so the header is complete — and
/// its size settled — on the first frame. The profile only fills a gap the
/// row leaves. It used to refine the title and location and append the
/// account's age, and paging between members then reflowed the header as
/// each profile landed; the age now sits on the Primary Contact card.
struct DealHeader: View {
    let deal: SellsideDeal?
    let profile: DealProfile?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let deal {
                HStack(alignment: .top, spacing: 12) {
                    CompanyMonogram(name: deal.displayName, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.title(deal: deal, profile: profile))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AxialColor.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle = deal.companySubtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(AxialColor.textSecondary)
                        }
                        if let facts = Self.facts(deal: deal, profile: profile) {
                            Text(facts)
                                .font(.footnote)
                                .foregroundStyle(AxialColor.textSecondary)
                                .contentTransition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !deal.attributes.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(deal.attributes, id: \.self) { attribute in
                            TagCapsule(text: attribute.label, palette: attribute.palette,
                                       systemImage: attribute.systemImage)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                HStack(spacing: 12) {
                    // No Interested label: the status already says where they
                    // stand, and the list they came from said the rest.
                    DealStatusLabel(status: deal.displayStatus)
                    Spacer(minLength: 8)
                    if let date = deal.statusDate {
                        Text("Updated \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(AxialColor.textPlaceholder)
                            .lineLimit(1)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: deal.displayStatus)
            } else {
                skeleton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Jordan Reyes at Bluewater Capital" — the sidebar's title. The row
    /// carries both names, so it doesn't wait for the profile; the profile's
    /// title is only for a row without them.
    static func title(deal: SellsideDeal, profile: DealProfile?) -> String {
        if let person = deal.demandUserName, !person.isEmpty,
           let account = deal.demandAccountName, !account.isEmpty, person != account {
            return "\(person) at \(account)"
        }
        return profile?.headerTitle ?? deal.displayName
    }

    /// Account type • location, joined as the web joins them, with " • ".
    /// The web's third part, years on Axial, is on the Primary Contact card.
    static func facts(deal: SellsideDeal, profile: DealProfile?) -> String? {
        let parts = [deal.companyType, deal.location ?? profile?.primaryOfficeLocation].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var skeleton: some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBox(width: 48, height: 48, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonText(lines: 2, style: .title3, lastLineWidth: 160)
                SkeletonBox(width: 120, height: 14, cornerRadius: 4)
            }
        }
        .shimmering()
        .accessibilityLabel("Loading member")
    }
}

/// A company's initials on a soft brand tile — the account icon the web
/// shows in the passport, without fetching an image for every deal.
struct CompanyMonogram: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(AccountInitials.from(name: name))
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(AxialColor.brandPrimary)
            .frame(width: size, height: size)
            .background(AxialColor.brandSubtle, in: RoundedRectangle(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

/// A person's headshot, or their initials while it loads or when there
/// isn't one.
struct PersonAvatar: View {
    let name: String
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(AccountInitials.from(name: name))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(AxialColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AxialColor.layer3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
