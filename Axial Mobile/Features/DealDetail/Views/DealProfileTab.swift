//
//  DealProfileTab.swift
//  Axial Mobile
//

import SwiftUI

/// The sidebar's Company Profile tab, in the web's order
/// (sell-sidebar.component.html): an inquiry's note, Overview, Industries of
/// Interest, Primary Contact, Additional Team Members, Offices, Sourcing
/// Criteria. Each section is one card and only appears when it has
/// something to say, as on the web.
///
/// Not here yet: the vetting answers the web shows first, behind its
/// `NEW_SELLSIDE_PROJECT_SETUP_VETTING_QUESTIONS_STEP` flag.
struct DealProfileTab: View {
    let deal: SellsideDeal?
    let profile: DealProfile?
    let error: String?
    let onRetry: () -> Void
    let onCopyEmail: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile {
                sections(profile)
                    .transition(.opacity)
            } else if let error {
                DealTabError(title: "Couldn't load this member's profile", message: error, onRetry: onRetry)
            } else {
                DealCardSkeleton(rows: 3)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: profile == nil)
    }

    @ViewBuilder
    private func sections(_ profile: DealProfile) -> some View {
        if deal?.supplyStatus == .targetRequestedAccess, let note = profile.inquiryNote {
            DealCard(title: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(profile.accountName ?? deal?.displayName ?? "This member") sent you a note regarding this deal:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                    ExpandableText(text: note, collapsedLines: 4,
                                   expandLabel: "Show Full Note", collapseLabel: "Show Less")
                }
            }
        }

        if profile.hasOverview {
            DealCard(title: "Overview") { overview(profile) }
        }

        if !profile.industries.isEmpty {
            DealCard(title: "Industries of Interest") {
                ExpandableTags(tags: profile.industries)
            }
        }

        if let contact = profile.contact {
            DealCard(title: "Primary Contact") { primaryContact(contact, profile: profile) }
        }

        if !profile.team.isEmpty {
            DealCard(title: "Additional Team Members") { TeamList(members: profile.team) }
        }

        if !profile.offices.isEmpty {
            DealCard(title: "Offices") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(profile.offices) { office in
                        OfficeRow(office: office)
                        if office.id != profile.offices.last?.id { Divider() }
                    }
                }
            }
        }

        if profile.showsSourcingCriteria {
            DealCard(title: "Sourcing Criteria") { sourcing(profile) }
        }
    }

    // MARK: Overview

    private func overview(_ profile: DealProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let closed = profile.closedDealsLine {
                FactRow(systemImage: "trophy", text: closed)
            }
            if profile.hasActivePortcos {
                FactRow(systemImage: "folder", text: "Has active portfolio companies")
            }
            if let behalf = profile.investingOnBehalfOf {
                FactRow(systemImage: "briefcase", text: behalf)
            }
            if let capital = profile.capitalSourceLine {
                FactRow(systemImage: "banknote", text: capital)
            }
            if let website = profile.website, let url = DealProfile.webURL(website) {
                Link(destination: url) {
                    FactRow(systemImage: "globe", text: website, isLink: true)
                }
            }
            if let about = profile.about {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                        .padding(.top, 4)
                    // The web truncates at 515 characters; lines are the
                    // phone's equivalent.
                    ExpandableText(text: about, collapsedLines: 6,
                                   expandLabel: "Show Full Description", collapseLabel: "Show Less")
                }
            }
        }
    }

    // MARK: Primary contact

    /// `axl-passport`: who they are, how to reach them, and their record.
    private func primaryContact(_ contact: DealProfile.Person, profile: DealProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PersonAvatar(name: contact.fullName, url: contact.headshotURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAnonymous(profile) ? "Axial Member" : contact.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                    if let title = contact.title {
                        Text(title).font(.caption).foregroundStyle(AxialColor.textSecondary)
                    }
                    if let account = profile.accountName {
                        Text(account).font(.caption).foregroundStyle(AxialColor.textSecondary)
                    }
                    // The web's header shows this; here it waits for the
                    // profile without moving the header.
                    if let age = profile.accountAge() {
                        Text(age).font(.caption).foregroundStyle(AxialColor.textPlaceholder)
                    }
                }
                Spacer(minLength: 0)
                if let url = contact.linkedInURL {
                    Link(destination: url) {
                        Image(systemName: "link.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AxialColor.brandPrimary)
                    }
                    .accessibilityLabel("\(contact.fullName) on LinkedIn")
                }
            }

            metrics(profile)

            // "Copy Email" only for a named member — `member.email &&
            // !contactedTargetRow.isAnonymous`.
            if let email = contact.email, !isAnonymous(profile) {
                Button {
                    onCopyEmail(email)
                } label: {
                    Label("Copy Email", systemImage: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(AxialColor.textPrimary)
                .accessibilityIdentifier("deal-copy-email")
            }
        }
    }

    private func isAnonymous(_ profile: DealProfile) -> Bool {
        deal?.isAnonymous ?? profile.isAnonymous
    }

    @ViewBuilder
    private func metrics(_ profile: DealProfile) -> some View {
        let rating = profile.rating ?? deal?.averageRating
        if profile.responsiveness == nil, profile.submittedBids == nil, rating == nil {
            Text("Member data not yet available")
                .font(.caption)
                .foregroundStyle(AxialColor.textPlaceholder)
        } else {
            // The project card's counts strip: an inset well, divided.
            HStack(spacing: 0) {
                MetricCell(title: "Responsiveness", value: profile.responsiveness.map { "\($0)%" })
                Divider().frame(height: 30)
                MetricCell(title: "Submitted Bids", value: profile.submittedBids.map(String.init))
                Divider().frame(height: 30)
                MetricCell(title: "Rating",
                           value: rating.map { $0.formatted(.number.precision(.fractionLength(1))) })
            }
            .padding(.vertical, 10)
            .insetWell()
        }
    }

    // MARK: Sourcing criteria

    private func sourcing(_ profile: DealProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if profile.revenueRange != nil || profile.ebitdaRange != nil {
                VStack(alignment: .leading, spacing: 6) {
                    subheading("Financial Ranges")
                    if let revenue = profile.revenueRange {
                        FactRow(systemImage: "checkmark.circle", text: "Revenue: \(revenue.formatted)")
                    }
                    // Only a closed range, as the web shows it.
                    if let ebitda = profile.ebitdaRange, ebitda.min != nil, ebitda.max != nil {
                        FactRow(systemImage: "checkmark.circle", text: "EBITDA: \(ebitda.formatted)")
                    }
                }
            }
            if !profile.sourcingIndustries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    subheading("Interested in Businesses Operating in")
                    ForEach(profile.sourcingIndustries, id: \.self) {
                        FactRow(systemImage: "building.2", text: $0)
                    }
                }
            }
            if profile.intentType == "buy_business", profile.client?.intentSubtype != "add_on",
               let description = profile.intentDescription {
                VStack(alignment: .leading, spacing: 6) {
                    subheading("Project Description")
                    ExpandableText(text: description, collapsedLines: 5,
                                   expandLabel: "Show More", collapseLabel: "Show Less")
                }
            }
        }
    }

    private func subheading(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AxialColor.textPrimary)
    }
}

// MARK: - Pieces

/// A titled card — the sidebar's sections, as the dashboard's cards.
struct DealCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionHeader(title: title)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct FactRow: View {
    let systemImage: String
    let text: String
    var isLink = false

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(isLink ? AxialColor.brandPrimary : AxialColor.textPrimary)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AxialColor.textPlaceholder)
        }
        .font(.subheadline)
    }
}

private struct MetricCell: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(value ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(AxialColor.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AxialColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// `axl-sell-sidebar-team`: four, then the rest on request.
private struct TeamList: View {
    let members: [DealProfile.Person]
    @State private var showsAll = false

    private var shown: [DealProfile.Person] {
        showsAll ? members : Array(members.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(shown) { member in
                HStack(spacing: 10) {
                    PersonAvatar(name: member.fullName, url: member.headshotURL, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.fullName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AxialColor.textPrimary)
                        if let title = member.title {
                            Text(title).font(.caption).foregroundStyle(AxialColor.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let url = member.linkedInURL {
                        Link(destination: url) {
                            Image(systemName: "link").foregroundStyle(AxialColor.brandPrimary)
                        }
                        .accessibilityLabel("\(member.fullName) on LinkedIn")
                    }
                }
            }
            if members.count > 4 {
                Button(showsAll ? "Show Fewer" : "Show All Members") {
                    Haptics.selection()
                    withAnimation(.snappy) { showsAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .tint(AxialColor.brandPrimary)
            }
        }
    }
}

private struct OfficeRow: View {
    let office: DealProfile.Office

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: office.isHeadquarters ? "building.columns" : "building")
                .foregroundStyle(AxialColor.textPlaceholder)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                if office.isHeadquarters {
                    Text("Headquarters")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AxialColor.textSecondary)
                }
                ForEach(office.street, id: \.self) { Text($0) }
                if !office.locality.isEmpty { Text(office.locality) }
                if let phone = office.phone {
                    Text(phone).foregroundStyle(AxialColor.textSecondary)
                }
            }
            .font(.subheadline)
            .foregroundStyle(AxialColor.textPrimary)
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Long text, clamped, with the web's Show Full / Show Less toggle. The
/// toggle only appears when there's more to show.
struct ExpandableText: View {
    let text: String
    let collapsedLines: Int
    var expandLabel = "Show More"
    var collapseLabel = "Show Less"

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AxialColor.textPrimary)
                .lineLimit(isExpanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                // Measure the full text against the clamped one, once per
                // width, to know whether a toggle is worth showing.
                .background {
                    ViewThatFits(in: .vertical) {
                        Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            .hidden().onAppear { isTruncated = false }
                        Color.clear.onAppear { isTruncated = true }
                    }
                }
            if isTruncated || isExpanded {
                Button(isExpanded ? collapseLabel : expandLabel) {
                    Haptics.selection()
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .tint(AxialColor.brandPrimary)
            }
        }
    }
}

/// Tags that can run long — a buyer can list dozens of industries — held
/// to about three rows, fading out at the cut, with Show All to open them
/// out. Short lists show whole, with no toggle. `ExpandableText`'s
/// controls, so the two read alike.
struct ExpandableTags: View {
    let tags: [String]
    /// About three rows of capsules.
    @ScaledMetric(relativeTo: .caption) private var collapsedHeight: CGFloat = 90

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var overflows: Bool { fullHeight > collapsedHeight + 1 }
    private var isClipped: Bool { overflows && !isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { TagCapsule(text: $0, palette: .plain) }
            }
            .fixedSize(horizontal: false, vertical: true)
            // The whole list's height, measured before the cap applies.
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
            .frame(height: isClipped ? collapsedHeight : nil, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [AxialColor.surface.opacity(0), AxialColor.surface],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                    .opacity(isClipped ? 1 : 0)
                    .allowsHitTesting(false)
            }
            // VoiceOver reads every tag whatever the cap.
            .accessibilityElement(children: .combine)

            if overflows {
                Button(isExpanded ? "Show Less" : "Show All \(tags.count)") {
                    Haptics.selection()
                    withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .tint(AxialColor.brandPrimary)
                .accessibilityIdentifier("industries-toggle")
            }
        }
    }
}

/// A tab's own failure, with a retry, when nothing was borrowed to show.
struct DealTabError: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        DealCard(title: nil) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AxialColor.textSecondary)
                Button("Retry", action: onRetry)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }
}

/// Placeholder cards while a tab's data is in flight.
struct DealCardSkeleton: View {
    var rows = 3

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<rows, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBox(width: 110, height: 12, cornerRadius: 4)
                    SkeletonText(lines: 3, style: .subheadline, lastLineWidth: 140)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}
