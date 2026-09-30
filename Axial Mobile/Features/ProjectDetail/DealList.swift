//
//  DealList.swift
//  Axial Mobile
//

import SwiftUI

/// A list of deals — contacted or interested, same row, different slice.
/// Lazy, because a busy project carries hundreds and the tab scrolls as one.
struct DealList: View {
    let deals: [SellsideDeal]
    let busyDealIds: Set<String>
    let emptyMessage: String
    let onAction: (SellsideDeal, DealActionRequest) -> Void

    var body: some View {
        if deals.isEmpty {
            EmptyStateCard(message: emptyMessage)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(deals) { deal in
                    DealRow(deal: deal, isBusy: busyDealIds.contains(deal.id)) { request in
                        onAction(deal, request)
                    }
                }
            }
        }
    }
}

/// Placeholder rows while a list is still in flight.
struct DealListSkeleton: View {
    var rows = 3

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonText(lines: 1, style: .subheadline, lastLineWidth: 180)
                    SkeletonBox(width: 96, height: 22, cornerRadius: 11)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
            }
        }
        .shimmering()
        .accessibilityElement()
        .accessibilityLabel("Loading members")
    }
}

/// The one card an empty tab shows, so empties read alike everywhere.
struct EmptyStateCard: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AxialColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AxialColor.border))
    }
}

/// Shared section heading: title plus an optional count.
struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
            if let count {
                Text("\(count)")
                    .foregroundStyle(AxialColor.textPlaceholder)
                    .contentTransition(.numericText())
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AxialColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
