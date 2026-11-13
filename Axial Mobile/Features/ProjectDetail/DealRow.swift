//
//  DealRow.swift
//  Axial Mobile
//

import SwiftUI

/// One member, as a card — enough to tell who it is, how good a fit, and
/// what it's waiting on. Everything else (every badge, the full profile) is
/// a tap away on the deal screen.
///
/// Draws on the web's member grids (contacted/interested/recommended-members-
/// grid.component.ts) in three parts:
///
/// 1. **Who** — monogram, company (and the account it acts through), type
///    and place, and the first two attribute badges.
/// 2. **The person and their record** — contact, closed deals, rating, on
///    one quiet line.
/// 3. **Where it stands** — status, interest, and when it last moved.
/// 4. **What's next** — the last message, one line, when there is one.
///
/// No action buttons on the card. Accept, Pass, Send CIM and Review Redlines
/// are swipes and menu items (`DealList`, `DealRowAction`), as the web keeps
/// them in its row's hover buttons rather than in the row itself.
struct DealRow: View {
    let deal: SellsideDeal
    let isBusy: Bool
    /// Where the card registers as the source its CIM note or redline
    /// editor zooms from.
    var transitionNamespace: Namespace.ID?
    /// Opens the deal — a tap anywhere on the card.
    var onOpen: (() -> Void)?
    /// Nil outside select mode; otherwise whether this card is selected.
    /// A tap then toggles it (`onOpen` is the toggle), and the card's own
    /// menu and buttons step aside.
    var selection: Bool?
    /// Off where the whole list is interested members — the Interested
    /// list and its drill-downs — where the label would say nothing.
    var showsInterest = true

    private var isSelecting: Bool { selection != nil }
    private var isSelected: Bool { selection == true }

    /// Shared with the zoom transitions out of the card.
    static let cornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CompanyMonogram(name: deal.displayName, size: 40)
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                // No ellipsis: a card's actions are its swipes and its long-
                // press menu, which is what we want sellers to reach for.
                // The select-mode check is always present and only takes
                // room while selecting, so the card doesn't rebuild.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                    .frame(width: isSelecting ? 28 : 0)
                    .opacity(isSelecting ? 1 : 0)
                    .accessibilityHidden(true)
            }

            if hasDetails {
                details
            }

            standing

            if let message = deal.lastMessagePreview {
                messageLine(message)
            }
        }
        .padding(16)
        .cardSurface(cornerRadius: Self.cornerRadius, border: isSelected ? AxialColor.brandPrimary : AxialColor.border)
        .overlay {
            // The 1pt border alone is too quiet for a selection.
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(AxialColor.brandPrimary, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: selection)
        // The CIM note and redline editor grow out of — and collapse back
        // into — the whole card, in its own shape.
        // Always applied, so the card's identity holds as its status moves.
        .zoomSource(id: sheetSourceID, in: transitionNamespace, cornerRadius: Self.cornerRadius)
        // A tap gesture rather than a Button, so the List row's swipes and
        // context menu aren't fighting a button's highlight.
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .onTapGesture {
            guard let onOpen else { return }
            isSelecting ? Haptics.selection() : Haptics.lightImpact()
            onOpen()
        }
        .accessibilityAction(named: isSelecting ? (isSelected ? "Deselect" : "Select") : "Open \(deal.displayName)") {
            onOpen?()
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // One element holding the card's parts, so a UI test can find,
        // tap and swipe the card by its id.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deal-card-\(deal.id)")
        .opacity(isBusy ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: deal.displayStatus)
    }

    // MARK: Who

    private var identity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(deal.displayName)
                .font(.headline)
                .foregroundStyle(AxialColor.textPrimary)
                .lineLimit(2)
            if let subtitle = deal.companySubtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textSecondary)
                    .lineLimit(1)
            }
            if let facts = Self.facts(for: deal) {
                Text(facts)
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textSecondary)
                    .lineLimit(1)
            }
            if !deal.attributes.isEmpty {
                badges
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The first two attribute badges, then a count — enough to spot a top
    /// pick or a closer without the wrapping row of every badge.
    private var badges: some View {
        let shown = deal.attributes.prefix(2)
        let more = deal.attributes.count - shown.count
        return FlowLayout(spacing: 6) {
            ForEach(Array(shown), id: \.self) { attribute in
                TagCapsule(text: attribute.label, palette: attribute.palette,
                           systemImage: attribute.systemImage)
            }
            if more > 0 {
                Text("+\(more)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AxialColor.textSecondary)
                    .padding(.vertical, 4)
                    .accessibilityLabel("and \(more) more")
            }
        }
    }

    /// What they are and where — "Private Equity Fund · Austin, TX".
    static func facts(for deal: SellsideDeal) -> String? {
        let parts = [deal.companyType, deal.location].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: The person and their record

    /// The member's name — when it isn't already the card's title — and
    /// title, if any.
    static func contact(for deal: SellsideDeal) -> String? {
        guard let name = deal.demandUserName, !name.isEmpty, name != deal.displayName else { return nil }
        guard let title = deal.title, !title.isEmpty else { return name }
        return "\(name), \(title)"
    }

    private var hasDetails: Bool {
        Self.contact(for: deal) != nil || deal.closedDeals > 0 || deal.averageRating != nil
    }

    /// One quiet line: who to talk to, then their track record. The name
    /// gives way first when space is short; the numbers always show.
    private var details: some View {
        HStack(spacing: 14) {
            if let contact = Self.contact(for: deal) {
                detail(contact, systemImage: "person")
                    .layoutPriority(-1)
            }
            if deal.closedDeals > 0 {
                detail("\(deal.closedDeals) closed", systemImage: "trophy")
                    .accessibilityLabel("\(deal.closedDeals) closed deal\(deal.closedDeals == 1 ? "" : "s")")
            }
            if let rating = deal.averageRating {
                detail(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                    .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(1)))) out of 5")
            }
            Spacer(minLength: 0)
        }
    }

    private func detail(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(AxialColor.textPlaceholder)
            Text(text)
                .lineLimit(1)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(AxialColor.textSecondary)
        .accessibilityElement(children: .combine)
    }

    // MARK: Where it stands

    private var standing: some View {
        HStack(spacing: 12) {
            DealStatusLabel(status: deal.displayStatus)
            if showsInterest, deal.isInterested {
                InterestedLabel()
            }
            Spacer(minLength: 8)
            if let date = deal.statusDate {
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(AxialColor.textPlaceholder)
                    .lineLimit(1)
                    .accessibilityLabel("Updated \(date.formatted(.relative(presentation: .named)))")
            }
        }
    }

    // MARK: What's next

    /// The latest message, one line, in an inset well so it reads as the
    /// conversation rather than more facts about the buyer. Unread gets the
    /// brand dot and count.
    private func messageLine(_ message: String) -> some View {
        let unread = deal.unreadMessageCount
        return HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.caption)
                .foregroundStyle(unread > 0 ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
            Text(message)
                .font(.footnote.weight(unread > 0 ? .semibold : .regular))
                .foregroundStyle(unread > 0 ? AxialColor.textPrimary : AxialColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if unread > 0 {
                Text(unread, format: .number)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AxialColor.brandPrimary, in: Capsule())
                    .accessibilityLabel("\(unread) unread")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AxialColor.inset, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    /// The sheet a swipe or menu can open from this card — the CIM note or
    /// the redline editor; a card never offers both — as the id that sheet
    /// zooms from.
    private var sheetSourceID: String {
        let action = DealResolveAction.offered(for: deal).first { $0 == .shareCim || $0 == .reviewRedlines }
        return action.map { DealResolution.cardSourceID(dealId: deal.id, action: $0) } ?? "\(deal.id).none"
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
        VStack(spacing: 14) {
            DealRow(
                deal: .init(publicId: "d1", demandAccountName: "Bluewater Capital",
                            demandUserName: "Jordan Reyes", supplyStatus: .targetSignedNda,
                            isInterested: true, demandAccountCode: "PE", closedDeals: 12,
                            title: "Managing Director", city: "Austin", stateProvince: "TX", country: "US",
                            lastMessage: "Thanks — we'll review the CIM this week and come back with questions.",
                            lastMessageFromFullName: "Jordan Reyes", newMessageCount: 2,
                            averageRating: 4.5, statusDate: now.addingTimeInterval(-3 * 86_400),
                            attributes: [.axialCloser, .closedDealsInYourSector, .highlyResponsiveBuyer]),
                isBusy: false
            )
            DealRow(
                deal: .init(publicId: "d2", demandAccountName: "Harbor Point Partners",
                            demandUserName: "Sam Okafor", supplyStatus: .sentTeaser, demandIsRead: true,
                            demandAccountCode: "PE", demandClientIntentSubtype: "add_on",
                            demandClientName: "Meridian Fabrication", city: "London", country: "GB",
                            statusDate: now.addingTimeInterval(-26 * 3_600)),
                isBusy: false
            )
            DealRow(
                deal: .init(publicId: "d3", demandAccountName: "Cypress Holdings",
                            supplyStatus: .recommended, demandAccountCode: "HC"),
                isBusy: true
            )
        }
        .padding(16)
    }
    .background(AxialColor.canvas)
}
