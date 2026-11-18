//
//  ProjectsRoute.swift
//  Axial Mobile
//

import Foundation

/// Everything the projects navigation stack can push.
///
/// A typed enum rather than a `NavigationPath` so the stack's shape is legible
/// in one place and the destinations are exhaustive.
enum ProjectsRoute: Hashable {
    /// A project's root screen — its dashboard.
    case project(id: String)

    /// One section of a project's members, pushed as its own screen —
    /// optionally opened with a filter already on, as a member breakdown bar
    /// does.
    case deals(projectId: String, bucket: SellsideDeal.Bucket, filter: DealFilter = DealFilter())

    /// A filtered slice of a project's members — where a dashboard action
    /// item or funnel stage drills to.
    case segment(projectId: String, segment: DealSegment)

    init(_ project: SellsideProject) {
        self = .project(id: project.intentId)
    }
}
