//
//  DealFunnelCard.swift
//  Axial Mobile
//

import SwiftUI

/// The dashboard's deal funnel, mirroring fe-app's `DealFlowFunnelComponent`
/// (deal-flow-funnel.component.ts).
///
/// The web's desktop layout puts the label left, the bar in a centred track
/// and "X% advance" right — three columns that don't fit a phone. Here each
/// row is two: the label with its conversion underneath, then the track. The
/// bars stay centred on one axis, so the stack still reads as a funnel, and
/// the counts sit inside them as on the web. Width and shade are positional,
/// as on the web — the shape never changes with the numbers.
struct DealFunnelCard: View {
    let funnel: DealFunnel
    let projectId: String
    /// Gates the "keep your statuses current" note: with nobody interested
    /// there's nothing to update. Counts *current* interested members, not
    /// the funnel's sticky flags. `hasInterestedMembers`.
    let hasInterestedMembers: Bool

    /// The widest label's natural width, so every row's label column matches
    /// and the bars share one centre line. Measured, not hardcoded, so it
    /// follows Dynamic Type.
    @State private var labelWidths: [FunnelStage: CGFloat] = [:]

    /// Only stages still on the funnel count — a stage that dropped out
    /// (CIM Viewed, Approved) would otherwise keep the column too wide.
    private var labelColumnWidth: CGFloat? {
        let current = Set(funnel.stages.map(\.stage))
        return labelWidths.filter { current.contains($0.key) }.values.max()
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 4) {
                    ForEach(funnel.stages) { stage in
                        row(stage)
                    }
                }
                if hasInterestedMembers {
                    statusNote
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ stage: DealFunnel.Stage) -> some View {
        if stage.stage.isDrillable {
            NavigationLink(value: ProjectsRoute.segment(projectId: projectId, segment: .funnelStage(stage.stage))) {
                rowBody(stage, showsChevron: true)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityHint("Shows these members")
            .accessibilityIdentifier("funnel-stage-\(stage.stage.rawValue)")
        } else {
            rowBody(stage, showsChevron: false)
                .accessibilityIdentifier("funnel-stage-\(stage.stage.rawValue)")
        }
    }

    private func rowBody(_ stage: DealFunnel.Stage, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(stage.stage.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
                Text(stage.advancePercent.map { "\($0)% advance" } ?? " ")
                    .font(.caption2)
                    .foregroundStyle(AxialColor.textSecondary)
            }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                labelWidths[stage.stage] = width
            }
            .frame(width: labelColumnWidth, alignment: .trailing)

            CenteredFraction(fraction: stage.widthFraction) {
                Text(stage.count, format: .number)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ChartPalette.funnelCountColor(at: stage.position))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(ChartPalette.funnelShade(at: stage.position), in: .rect(cornerRadius: 4))
            }

            // Kept on undrillable rows too, hidden, so every track is the
            // same width and the centre line holds.
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AxialColor.textPlaceholder)
                .opacity(showsChevron ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.stage.label)
        .accessibilityValue(accessibilityValue(stage))
    }

    private func accessibilityValue(_ stage: DealFunnel.Stage) -> String {
        let members = "\(stage.count) member\(stage.count == 1 ? "" : "s")"
        guard let percent = stage.advancePercent else { return members }
        return "\(members), \(percent) percent of the previous stage"
    }

    /// The web's inline notification under the funnel (sc-34923).
    private var statusNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("This funnel reflects the statuses of interest on Axial. If any data is incorrect, please update members' statuses. This data impacts your ability to receive owner referrals and Axial marketing awards.")
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(AxialColor.brandPrimary)
            }
            NavigationLink("Update Member Statuses",
                           value: ProjectsRoute.deals(projectId: projectId, bucket: .interested))
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.leading, 28)
                .accessibilityIdentifier("funnel-update-statuses")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TagPalette.blue.background, in: .rect(cornerRadius: 10))
    }
}

/// Places its one child centred, at a fraction of the width it's offered —
/// but never narrower than the child needs, so a small count can't be
/// clipped. The web's `width: N%; min-width: fit-content`. A `Layout` rather
/// than a `GeometryReader` per row.
private struct CenteredFraction: Layout {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? ideal.width, height: ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let minimum = child.sizeThatFits(.unspecified).width
        let width = min(bounds.width, max(bounds.width * fraction, minimum))
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }
}

#Preview {
    let progress: [Set<FunnelStage>] = [
        [.teaserSent], [.teaserSent, .teaserOpened],
        [.teaserSent, .teaserOpened, .interested, .ndaSent],
        [.teaserSent, .teaserOpened, .interested, .ndaSent, .ndaSigned, .cimSent],
        [.teaserSent, .teaserOpened, .interested, .ndaSent, .ndaSigned, .cimSent, .ioiReceived, .loiReceived],
    ]
    let deals = progress.enumerated().map { index, reached in
        SellsideDeal(publicId: "d\(index)", isInterested: reached.contains(.interested),
                     progress: DealProgress(reached: reached))
    }
    let dashboard = ProjectDashboard(
        project: ProjectDetail(id: "abc", internalName: "Neptune", supplyState: .inMarket), deals: deals)
    NavigationStack {
        ScrollView {
            DealFunnelCard(funnel: DealFunnel(dashboard: dashboard), projectId: "abc", hasInterestedMembers: true)
                .padding(16)
        }
        .background(AxialColor.layer2)
    }
}
