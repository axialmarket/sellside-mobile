//
//  DealRow.swift
//  Axial Mobile
//

import SwiftUI

/// One contacted member: who they are, where the deal stands, and what can be
/// done about it.
struct DealRow: View {
    let deal: SellsideDeal
    let isBusy: Bool
    let onAction: (DealActionRequest) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(deal.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(2)

                if let contact = deal.demandUserName, !contact.isEmpty,
                   contact != deal.displayName {
                    Text(contact)
                        .font(.caption)
                        .foregroundStyle(AxialColor.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    DealStatusTag(status: deal.displayStatus)
                    if deal.isInterested {
                        TagCapsule(text: "Interested", palette: .green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DealActionsMenu(deal: deal, isBusy: isBusy, onSelect: onAction)
        }
        .padding(14)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
        .opacity(isBusy ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: deal.displayStatus)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 10) {
            DealRow(
                deal: .init(publicId: "d1", demandAccountName: "Bluewater Capital",
                            demandUserName: "Jordan Reyes", supplyStatus: .sentTeaser,
                            demandIsRead: true),
                isBusy: false, onAction: { _ in }
            )
            DealRow(
                deal: .init(publicId: "d2", demandAccountName: "Harbor Point Partners",
                            supplyStatus: .markedReceivedLoi, isInterested: true),
                isBusy: false, onAction: { _ in }
            )
            DealRow(
                deal: .init(publicId: "d3", demandAccountName: "Cypress Holdings",
                            supplyStatus: .targetExpired),
                isBusy: true, onAction: { _ in }
            )
        }
        .padding(16)
    }
    .background(AxialColor.layer2)
}
