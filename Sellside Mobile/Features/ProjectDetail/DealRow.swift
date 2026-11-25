//
//  DealRow.swift
//  Sellside Mobile
//

import SwiftUI

/// One member, as a card — enough to tell who it is, how good a fit, and
/// what it's waiting on. Everything else (the full profile, every message)
/// is a tap away on the deal screen.
///
/// Laid out like the buyside app's deal card (fe-app's buyside deal tiles):
/// a bold title, a few icon-led facts, a rule, then the figures that
/// matter in large type — with one row of tags under the facts. The content
/// is the sellside grids' (contacted/interested/recommended-members-
/// grid.component.ts):
///
/// 1. **Title** — the company (and the account it acts through), with the
///    status and when it last moved in the top trailing corner, where the
///    project card keeps its status.
/// 2. **Facts** — company type, and who to talk to with their rating.
/// 3. **Tags** — Interested and the buyer's attribute badges, one row, as
///    many as fit and a "+N more" for the rest.
/// 4. **Figures** — Acquirer Type and Closed Deals.
/// 5. **What's next** — the last message, one line, when there is one.
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
    /// Off in Recommended, where every member is Deal Not Shared.
    var showsStatus = true

    private var isSelecting: Bool { selection != nil }
    private var isSelected: Bool { selection == true }

    /// Shared with the zoom transitions out of the card.
    static let cornerRadius = AxialRadius.card

    var body: some View {
        let tags = tags
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsStatus || deal.statusDate != nil {
                    standing
                }
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

            facts

            if !tags.isEmpty {
                tagRow(tags)
            }

            Divider()

            figures

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

    // MARK: Title

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Facts

    /// Icon-led lines, the buyside card's location and sector rows. Each
    /// shows only when there's something to say. Location is left to the
    /// deal screen; the card keeps what a seller weighs a buyer by.
    @ViewBuilder
    private var facts: some View {
        let contact = Self.contact(for: deal)
        if deal.companyType != nil || contact != nil || deal.averageRating != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let type = deal.companyType {
                    fact(type, systemImage: "building.2")
                }
                if contact != nil || deal.averageRating != nil {
                    HStack(spacing: 12) {
                        if let contact {
                            fact(contact, systemImage: "person")
                                .layoutPriority(-1)
                        }
                        Spacer(minLength: 0)
                        if let rating = deal.averageRating {
                            rated(rating)
                        }
                    }
                }
            }
        }
    }

    /// The member's name — when it isn't already the card's title — and
    /// title, if any.
    static func contact(for deal: SellsideDeal) -> String? {
        guard let name = deal.demandUserName, !name.isEmpty, name != deal.displayName else { return nil }
        guard let title = deal.title, !title.isEmpty else { return name }
        return "\(name), \(title)"
    }

    private func fact(_ text: String, systemImage: String) -> some View {
        FactLabel(text: text, systemImage: systemImage)
    }

    private func rated(_ rating: Double) -> some View {
        let text = rating.formatted(.number.precision(.fractionLength(1)))
        return Label(text, systemImage: "star.fill")
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(AxialColor.textSecondary)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .fixedSize()
            .accessibilityLabel("Rated \(text) out of 5")
    }

    // MARK: Tags

    /// Interested, then the buyer's badges in the backend's order and the
    /// web's colours.
    private var tags: [Tag] {
        var items: [Tag] = []
        if showsInterest, deal.isInterested {
            items.append(Tag(id: "interested", text: "Interested",
                             systemImage: "hand.thumbsup.fill", palette: .green))
        }
        items += deal.attributes.map {
            Tag(id: $0.rawValue, text: $0.label, systemImage: $0.systemImage, palette: $0.palette)
        }
        return items
    }

    private struct Tag: Identifiable {
        let id: String
        let text: String
        let systemImage: String
        let palette: TagPalette
    }

    /// One row: as many tags as fit whole, then "+N more" for the rest. Each
    /// candidate row holds one tag fewer than the last, and `ViewThatFits`
    /// takes the first that fits the card, so a tag is never cut off.
    private func tagRow(_ all: [Tag]) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(0..<all.count, id: \.self) { hidden in
                HStack(spacing: 6) {
                    ForEach(all.prefix(all.count - hidden)) { tag in
                        TagCapsule(text: tag.text, palette: tag.palette, systemImage: tag.systemImage)
                    }
                    if hidden > 0 {
                        TagCapsule(text: "+\(hidden) more", palette: .plain)
                            .accessibilityLabel("and \(hidden) more")
                    }
                }
                .fixedSize()
            }
        }
    }

    // MARK: Figures

    /// The buyside card's Revenue and EBITDA: label over a large value, two
    /// columns. A missing or nothing value is quiet.
    private var figures: some View {
        HStack(alignment: .top, spacing: 12) {
            figure("Acquirer Type", value: deal.acquirerType.label, isMuted: deal.acquirerType == .other)
            figure("Closed Deals", value: deal.closedDeals.formatted(), isMuted: deal.closedDeals == 0)
        }
    }

    private func figure(_ label: String, value: String, isMuted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(AxialColor.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(isMuted ? AxialColor.textPlaceholder : AxialColor.textPrimary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Where it stands

    /// Top trailing, as on the project card: the status, and under it when
    /// it last moved, so the two read together ("NDA Signed, 3 days ago")
    /// and the time never needs a row of its own. In Recommended, where
    /// there's no status, just the time.
    ///
    /// A spinner takes the status's place while a change to this member
    /// runs; both are always there, so the header keeps its shape.
    private var standing: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if showsStatus {
                DealStatusLabel(status: deal.displayStatus)
                    .opacity(isBusy ? 0 : 1)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .opacity(isBusy ? 1 : 0)
                    }
                    .animation(.easeOut(duration: 0.15), value: isBusy)
            }
            if let date = deal.statusDate {
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(AxialColor.textPlaceholder)
                    .lineLimit(1)
                    .accessibilityLabel("Updated \(date.formatted(.relative(presentation: .named)))")
            }
        }
        .fixedSize()
        .padding(.top, 2)
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
        .insetWell()
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
