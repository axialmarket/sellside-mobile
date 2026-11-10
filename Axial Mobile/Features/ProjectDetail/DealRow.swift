//
//  DealRow.swift
//  Axial Mobile
//

import SwiftUI

/// One member, as a card. Draws on the leading columns of the web's member
/// grids (contacted/interested/recommended-members-grid.component.ts) —
/// Company, Status, Last Updated, Last Message, Company Type, Location,
/// Closed Deals, Member Name, Rating — in three bands:
///
/// 1. **Who** — company (with the account it acts for), type, place, track
///    record, and any attribute badges. The menu sits beside it.
/// 2. **Where it stands** — status, interest, and when it last moved. Not
///    capsules, so it can't be mistaken for one of the badges above it.
/// 3. **The person and the conversation** — only when there's something to
///    say, so a fresh recommendation stays a compact card.
///
/// Every list shows the same card for now; the bands are where a list would
/// diverge (Recommended has no conversation yet; Interested would want the
/// signed NDA).
struct DealRow: View {
    let deal: SellsideDeal
    let isBusy: Bool
    /// Where the card's resolve buttons register as zoom sources.
    var transitionNamespace: Namespace.ID?
    /// Opens the deal. The card's own buttons and menu still take their
    /// taps; anywhere else on the card opens it.
    var onOpen: (() -> Void)?
    let onAction: (DealActionRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                DealActionsMenu(deal: deal, isBusy: isBusy, onSelect: onAction)
            }

            if !deal.attributes.isEmpty {
                attributeTags
            }

            standing

            if hasPersonBand {
                Divider()
                personBand
            }

            if !resolveActions.isEmpty {
                resolveBand
            }
        }
        .padding(14)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
        // The CIM note and redline editor grow out of — and collapse back
        // into — the whole card, in its own shape, not the glass button.
        // Always applied, so the card's identity holds as its status moves.
        .zoomSource(id: sheetSourceID, in: transitionNamespace, cornerRadius: 14)
        // A tap gesture rather than wrapping the card in a Button, so the
        // resolve buttons and the menu inside it keep their own taps.
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard let onOpen else { return }
            Haptics.lightImpact()
            onOpen()
        }
        .accessibilityAction(named: "Open \(deal.displayName)") { onOpen?() }
        .opacity(isBusy ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: deal.displayStatus)
    }

    // MARK: Who

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deal.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AxialColor.textPrimary)
                .lineLimit(2)
            if let subtitle = deal.companySubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AxialColor.textSecondary)
                    .lineLimit(1)
            }
            if let facts = Self.facts(for: deal) {
                Text(facts)
                    .font(.caption)
                    .foregroundStyle(AxialColor.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Private Equity Fund · Austin, TX · 12 closed deals".
    static func facts(for deal: SellsideDeal) -> String? {
        let closed = deal.closedDeals > 0
            ? "\(deal.closedDeals) closed deal\(deal.closedDeals == 1 ? "" : "s")"
            : nil
        let parts = [deal.companyType, deal.location, closed].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The web's Attributes column (`determineAttributes`): one coloured tag
    /// per badge, wrapping when a long one ("Closed Deals in Your Sector")
    /// won't share a line.
    private var attributeTags: some View {
        FlowLayout(spacing: 6) {
            ForEach(deal.attributes, id: \.self) { attribute in
                TagCapsule(text: attribute.label, palette: attribute.palette,
                           systemImage: attribute.systemImage)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Where it stands

    private var standing: some View {
        HStack(spacing: 12) {
            DealStatusLabel(status: deal.displayStatus)
            if deal.isInterested {
                InterestedLabel()
            }
            Spacer(minLength: 8)
            if let date = deal.statusDate {
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption2)
                    .foregroundStyle(AxialColor.textPlaceholder)
                    .lineLimit(1)
                    .accessibilityLabel("Updated \(date.formatted(.relative(presentation: .named)))")
            }
        }
    }

    // MARK: What it's waiting on you for

    private var resolveActions: [DealResolveAction] {
        DealResolveAction.offered(for: deal)
    }

    /// The one action on a card that opens a sheet, if any — a card never
    /// offers both — as the id the resolver's sheet zooms from.
    private var sheetSourceID: String {
        let action = resolveActions.first { $0 == .shareCim || $0 == .reviewRedlines }
        return action.map { DealResolution.cardSourceID(dealId: deal.id, action: $0) } ?? "\(deal.id).none"
    }

    /// The web sidebar's primary buttons, on the card — so a member waiting
    /// on the seller can be moved on from the list itself. Separate lenses
    /// with room between them: a shared `GlassEffectContainer` merged Pass
    /// and Accept while one was pressed.
    private var resolveBand: some View {
        HStack(spacing: 12) {
            ForEach(resolveActions) { action in
                Button {
                    Haptics.lightImpact()
                    onAction(.resolve(action))
                } label: {
                    Label(action.label(for: deal), systemImage: action.systemImage)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .modifier(ResolveButtonStyle(isPrimary: action.isPrimary))
                .accessibilityIdentifier("deal-resolve-\(action)")
            }
        }
        .disabled(isBusy)
    }

    // MARK: The person and the conversation

    private var memberLine: String? {
        guard let name = deal.demandUserName, !name.isEmpty, name != deal.displayName else { return nil }
        guard let title = deal.title, !title.isEmpty else { return name }
        return "\(name) · \(title)"
    }

    private var hasPersonBand: Bool {
        memberLine != nil || deal.averageRating != nil || deal.lastMessagePreview != nil
    }

    private var personBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            if memberLine != nil || deal.averageRating != nil {
                HStack(spacing: 8) {
                    if let memberLine {
                        bandLabel(memberLine, systemImage: "person", lines: 1)
                    }
                    Spacer(minLength: 0)
                    if let rating = deal.averageRating {
                        Label {
                            Text(rating, format: .number.precision(.fractionLength(1)))
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "star.fill")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AxialColor.textSecondary)
                        .labelStyle(.titleAndIcon)
                        .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1)))) out of 5")
                    }
                }
            }
            if let message = deal.lastMessagePreview {
                HStack(alignment: .top, spacing: 8) {
                    bandLabel(message, systemImage: "bubble.left", lines: 2)
                    Spacer(minLength: 0)
                    if deal.unreadMessageCount > 0 {
                        Text("\(deal.unreadMessageCount) new")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AxialColor.brandPrimary, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    private func bandLabel(_ text: String, systemImage: String, lines: Int) -> some View {
        Label {
            Text(text)
                .lineLimit(lines)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AxialColor.textPlaceholder)
        }
        .font(.caption)
        .foregroundStyle(AxialColor.textSecondary)
    }
}

/// Tinted glass for the primary action, clear glass for the secondary one —
/// content buttons, so `.glass` rather than a bar's bordered style.
private struct ResolveButtonStyle: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.glassProminent).tint(AxialColor.brandPrimary)
        } else {
            content.buttonStyle(.glass).tint(AxialColor.textPrimary)
        }
    }
}

extension BuysideAttribute {
    /// `ROW_ITEM_TAGS[…].color`.
    var palette: TagPalette {
        switch self {
        case .axialCloser: .green
        case .closedDealsInYourSector: .purple
        case .highlyResponsiveBuyer: .orange
        case .topPick: .blue
        case .portfolioCompany, .referral, .inboundInquiry, .unknown: .plain
        }
    }

    /// SF Symbols standing in for `ROW_ITEM_TAGS[…].leftIcon` (Remix).
    var systemImage: String {
        switch self {
        case .axialCloser, .closedDealsInYourSector: "trophy"
        case .highlyResponsiveBuyer: "person.wave.2"
        case .inboundInquiry: "envelope"
        case .portfolioCompany: "folder"
        case .referral: "person.2"
        case .topPick: "rosette"
        case .unknown: "tag"
        }
    }
}

#Preview {
    let now = Date.now
    ScrollView {
        VStack(spacing: 10) {
            DealRow(
                deal: .init(publicId: "d1", demandAccountName: "Bluewater Capital",
                            demandUserName: "Jordan Reyes", supplyStatus: .targetSignedNda,
                            isInterested: true, demandAccountCode: "PE", closedDeals: 12,
                            title: "Managing Director", city: "Austin", stateProvince: "TX", country: "US",
                            lastMessage: "Thanks — we'll review the CIM this week and come back with questions.",
                            lastMessageFromFullName: "Jordan Reyes", newMessageCount: 2,
                            averageRating: 4.5, statusDate: now.addingTimeInterval(-3 * 86_400),
                            attributes: [.axialCloser, .closedDealsInYourSector, .highlyResponsiveBuyer]),
                isBusy: false, onAction: { _ in }
            )
            DealRow(
                deal: .init(publicId: "d2", demandAccountName: "Harbor Point Partners",
                            demandUserName: "Sam Okafor", supplyStatus: .sentTeaser, demandIsRead: true,
                            demandAccountCode: "PE", demandClientIntentSubtype: "add_on",
                            demandClientName: "Meridian Fabrication", city: "London", country: "GB",
                            statusDate: now.addingTimeInterval(-26 * 3_600)),
                isBusy: false, onAction: { _ in }
            )
            DealRow(
                deal: .init(publicId: "d3", demandAccountName: "Cypress Holdings",
                            supplyStatus: .recommended, demandAccountCode: "HC"),
                isBusy: true, onAction: { _ in }
            )
        }
        .padding(16)
    }
    .background(AxialColor.layer2)
}
