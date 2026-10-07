//
//  MemberBreakdownCard.swift
//  Axial Mobile
//

import SwiftUI
import Charts

/// The dashboard's member breakdown, mirroring fe-app's
/// `MemberBreakdownComponent` (member-breakdown.component.ts).
///
/// The web draws vertical bars with the bucket names underneath. At phone
/// width those names collide, and short bars read as stubs, so the bars run
/// horizontally here: names in a two-line column on the leading side, each
/// count at the end of its bar. Same buckets, same colours, same order.
struct MemberBreakdownCard: View {
    let dashboard: ProjectDashboard

    /// Nil until the seller picks, so the default can follow the data — once
    /// chosen it sticks, as on the web (`selectedMemberList`).
    @State private var chosenList: SellsideDeal.Bucket?
    @State private var dimension: MemberBreakdown.Dimension = .companyType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lists: [SellsideDeal.Bucket] {
        MemberBreakdown.availableLists(in: dashboard)
    }

    /// The chosen list while it's still offered — SmartShare can take
    /// Recommended away — else the default.
    private var list: SellsideDeal.Bucket {
        if let chosenList, lists.contains(chosenList) { return chosenList }
        return MemberBreakdown.defaultList(in: dashboard)
    }

    private var bars: [MemberBreakdown.Bar] {
        MemberBreakdown.bars(for: dashboard.deals(in: list), by: dimension)
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    picker("Breakdown By", selection: $dimension, options: MemberBreakdown.Dimension.allCases) {
                        $0.label
                    }
                    .accessibilityIdentifier("breakdown-dimension")
                    picker("Member List", selection: listBinding, options: lists) { $0.title }
                        .accessibilityIdentifier("breakdown-list")
                }

                ZStack(alignment: .topLeading) {
                    if bars.isEmpty {
                        Text("No members in this list yet.")
                            .font(.footnote)
                            .foregroundStyle(AxialColor.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .transition(.opacity)
                    } else {
                        chart
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: bars.isEmpty)
            }
        }
    }

    /// The bucket-name column. Narrow enough to leave the bars most of the
    /// card; the longest name ("Individual Accredited Investor") wraps to two
    /// lines in it. Scales with Dynamic Type so wrapping doesn't turn into
    /// truncation at larger sizes.
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 110
    /// Thickness of each bar, and the row it and its name sit in — tall
    /// enough for a two-line name.
    @ScaledMetric(relativeTo: .caption) private var barThickness: CGFloat = 26
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 40

    /// The names are our own column rather than the chart's y-axis: Swift
    /// Charts sizes axis labels for one line, so two-line names spilled over
    /// the bars. With the category scale's padding removed, the chart splits
    /// its height into equal rows, one per bar — the same rows the name
    /// column uses — so the two line up exactly.
    private var chart: some View {
        let maxCount = bars.map(\.count).max() ?? 1
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .font(.caption)
                        .foregroundStyle(AxialColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(width: labelWidth, height: rowHeight, alignment: .trailing)
                }
            }
            // The bars carry the same names for VoiceOver.
            .accessibilityHidden(true)

            Chart(bars) { bar in
                BarMark(
                    x: .value("Members", bar.count),
                    y: .value("Group", bar.label),
                    height: .fixed(barThickness)
                )
                .foregroundStyle(bar.swatch.color)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                .annotation(position: .trailing, spacing: 6) {
                    Text(bar.count, format: .number)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AxialColor.textSecondary)
                }
                .accessibilityLabel(bar.label)
                .accessibilityValue("\(bar.count) member\(bar.count == 1 ? "" : "s")")
            }
            // Headroom past the longest bar for its count.
            .chartXScale(domain: 0...(Double(maxCount) * 1.2))
            .chartYScale(range: .plotDimension(padding: 0))
            // Counts sit at the end of each bar; the names are alongside.
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
        .frame(height: CGFloat(bars.count) * rowHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: bars)
    }

    private var listBinding: Binding<SellsideDeal.Bucket> {
        Binding(get: { list }, set: { chosenList = $0 })
    }

    /// A captioned menu picker — the web's labelled dropdown.
    private func picker<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AxialColor.textSecondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(AxialColor.textPrimary)
            // Menu pickers carry their own inset; line the value up with the
            // caption above it.
            .padding(.leading, -8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let codes = ["PE", "PE", "PE", "FO", "C", "HC", "XX", "PF", "PF"]
    let deals = codes.enumerated().map { index, code in
        SellsideDeal(publicId: "d\(index)", supplyStatus: .sentTeaser, isInterested: index % 2 == 0,
                     demandAccountCode: code, capitalSource: index % 3 == 0 ? .committed : nil,
                     closedDeals: index)
    }
    let dashboard = ProjectDashboard(
        project: ProjectDetail(id: "abc", internalName: "Neptune", supplyState: .inMarket), deals: deals)
    ScrollView {
        MemberBreakdownCard(dashboard: dashboard)
            .padding(16)
    }
    .background(AxialColor.layer2)
}
