//
//  DealFunnel.swift
//  Sellside Mobile
//

import Foundation

/// The dashboard's deal funnel: how many members ever reached each stage.
///
/// Mirrors fe-app's `SellDashboardStore.funnelStages` (sell-dashboard.store.ts)
/// for the counts and `buildFunnelStageViews` (deal-flow-funnel.model.ts) for
/// the shape.
struct DealFunnel: Equatable {
    struct Stage: Identifiable, Equatable {
        let stage: FunnelStage
        let count: Int
        /// This bar's width as a fraction of the track, set by its position
        /// alone — the funnel looks the same whatever the numbers.
        let widthFraction: Double
        /// This stage's count over the previous one's, as a rounded
        /// percentage. Nil on the first stage, and when the previous stage
        /// is empty.
        let advancePercent: Int?
        /// 0 for the top bar; drives the shade ramp.
        let position: Int

        var id: FunnelStage { stage }
    }

    /// The top bar fills the track; the bottom one tapers to 18%.
    static let topWidth = 1.0
    static let bottomWidth = 0.18

    let stages: [Stage]

    init(dashboard: ProjectDashboard) {
        let deals = dashboard.deals
        let interested = deals.filter(\.isInterested)
        let applicable = Self.applicableStages(dashboard)

        let counts = applicable.map { stage in
            (stage.countsEveryMember ? deals : interested).count { $0.progress.has(stage) }
        }
        let step = applicable.count > 1
            ? (Self.topWidth - Self.bottomWidth) / Double(applicable.count - 1)
            : 0

        stages = applicable.enumerated().map { index, stage in
            let previous = index > 0 ? counts[index - 1] : 0
            return Stage(
                stage: stage,
                count: counts[index],
                widthFraction: Self.topWidth - Double(index) * step,
                advancePercent: previous > 0
                    ? Int((Double(counts[index]) / Double(previous) * 100).rounded())
                    : nil,
                position: index
            )
        }
    }

    /// Every stage applies but two:
    /// - **Approved** only when outreach is gated on a pitch — the project
    ///   requires it, or at least one deal does. Same rule as the contacted
    ///   grid's "Outreach Type" column.
    /// - **CIM Viewed** only once there's a CIM to view.
    static func applicableStages(_ dashboard: ProjectDashboard) -> [FunnelStage] {
        let gatedOnPitch = dashboard.project.requiresApproval
            || dashboard.deals.contains(where: \.requiresApproval)
        return FunnelStage.allCases.filter { stage in
            switch stage {
            case .pursued: gatedOnPitch
            case .cimViewed: dashboard.project.hasCim
            default: true
            }
        }
    }
}
