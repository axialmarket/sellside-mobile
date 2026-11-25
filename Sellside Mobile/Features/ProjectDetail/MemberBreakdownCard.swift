//
//  MemberBreakdownCard.swift
//  Sellside Mobile
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
///
/// Each bar drills in, as the funnel's stages do: it pushes the chosen
/// member list with that bar's filter applied (`MemberBreakdown.filter`).
struct MemberBreakdownCard: View {
    let dashboard: ProjectDashboard
    let projectId: String

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

    /// One animation for a picked option: the menu's label, the bars and the
    /// card's height all move together, in the same transaction as the
    /// change, rather than the label jumping while the menu closes.
    private var changeAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
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
                .animation(changeAnimation, value: bars.isEmpty)
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
    ///
    /// Rows are keyed by position, not by bucket name, and there are always
    /// as many as the busiest dimension can fill (`maxBarCount`); the card
    /// shows only the top `bars.count` of them. Rows past the last bar hold
    /// a zero-length bar and no name.
    ///
    /// That way nothing is ever inserted into or removed from the chart. A
    /// switch that adds bars grows the card, and the new bars grow out from
    /// zero as it does; one that drops them shrinks theirs to zero as the
    /// card closes over them. Bars that stay resize in place while their
    /// names and counts cross-fade. Keyed by name, the chart dropped every
    /// bar and drew new ones (a blank moment), and added bars popped in.
    private var chart: some View {
        let shown = bars
        let rows = MemberBreakdown.maxBarCount
        let maxCount = shown.map(\.count).max() ?? 1
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    Text(row < shown.count ? shown[row].label : "")
                        .font(.caption)
                        .foregroundStyle(AxialColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .contentTransition(.interpolate)
                        .frame(width: labelWidth, height: rowHeight, alignment: .trailing)
                        .opacity(row < shown.count ? 1 : 0)
                }
            }

            Chart {
                ForEach(0..<rows, id: \.self) { row in
                    let bar = row < shown.count ? shown[row] : nil
                    BarMark(
                        x: .value("Members", bar?.count ?? 0),
                        y: .value("Row", String(row)),
                        height: .fixed(barThickness)
                    )
                    .foregroundStyle(bar?.swatch.color ?? .clear)
                    .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                    .annotation(position: .trailing, spacing: 6) {
                        Text(bar?.count ?? 0, format: .number)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(bar?.count ?? 0)))
                            .foregroundStyle(AxialColor.textSecondary)
                            .opacity(bar == nil ? 0 : 1)
                    }
                }
            }
            // Headroom past the longest bar for its count.
            .chartXScale(domain: 0...(Double(maxCount) * 1.2))
            .chartYScale(range: .plotDimension(padding: 0))
            // Counts sit at the end of each bar; the names are alongside.
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

            // The funnel's affordance: a chevron per drillable row.
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AxialColor.textPlaceholder)
                        .frame(height: rowHeight)
                        .opacity(row < shown.count ? 1 : 0)
                }
            }
        }
        // Every row laid out, so the chart's rows match the name column's.
        .frame(height: CGFloat(rows) * rowHeight, alignment: .top)
        // Only the rows with bars show; the card grows and shrinks with them.
        .frame(height: CGFloat(shown.count) * rowHeight, alignment: .top)
        .clipped()
        // The rows below speak for the chart.
        .accessibilityHidden(true)
        .overlay { barLinks }
        // A refresh that changes the counts, as well as a picked option.
        .animation(changeAnimation, value: bars)
    }

    /// One link per row, laid over name, bar and chevron, so the whole row
    /// is the target rather than a bar that can be a sliver wide. Same rows
    /// as the chart, so each lines up with its bar.
    private var barLinks: some View {
        let members = dashboard.deals(in: list)
        return VStack(spacing: 0) {
            ForEach(bars.indices, id: \.self) { row in
                let bar = bars[row]
                NavigationLink(value: ProjectsRoute.deals(
                    projectId: projectId, bucket: list,
                    filter: MemberBreakdown.filter(for: bar, by: dimension, in: members)
                )) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BarRowButtonStyle())
                .accessibilityLabel(bar.label)
                .accessibilityValue("\(bar.count) member\(bar.count == 1 ? "" : "s")")
                .accessibilityHint("Shows these members")
                .accessibilityIdentifier("breakdown-bar-\(bar.id)")
            }
        }
    }

    private var listBinding: Binding<SellsideDeal.Bucket> {
        Binding(get: { list }, set: { chosenList = $0 })
    }

    /// A captioned dropdown — the web's labelled select, sized down.
    ///
    /// The system menu picker draws a full-size button, which made the two
    /// controls the loudest thing on the card. Here the caption and value
    /// together are the menu's label: small type, but the whole stack is the
    /// target, and it's held to the 44pt minimum.
    private func picker<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Menu {
            // Inline inside a menu, so the current choice gets its checkmark.
            Picker(title, selection: selection.animation(changeAnimation)) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AxialColor.textSecondary)
                HStack(spacing: 4) {
                    Text(label(selection.wrappedValue))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                        .lineLimit(1)
                        // Cross-fades into the new choice instead of
                        // snapping to a new width as the menu collapses.
                        .contentTransition(.interpolate)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .imageScale(.small)
                        .foregroundStyle(AxialColor.textSecondary)
                }
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(label(selection.wrappedValue))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A faint wash over the row while it's pressed — the bars underneath stay
/// visible, unlike a solid highlight.
private struct BarRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                AxialColor.textPrimary.opacity(configuration.isPressed ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
        NavigationStack {
            MemberBreakdownCard(dashboard: dashboard, projectId: "abc")
                .padding(16)
        }
    }
    .background(AxialColor.canvas)
}
