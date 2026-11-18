//
//  ProjectSummary.swift
//  Axial Mobile
//

import Foundation

/// The little a project's header needs, which both the list row and the full
/// project can supply. Lets the dashboard render its header the instant you
/// tap a card — from state we already hold — instead of skeletoning data
/// that's sitting right there.
struct ProjectSummary: Equatable {
    let internalName: String
    let supplyState: SupplyState

    init(_ detail: ProjectDetail) {
        internalName = detail.internalName
        supplyState = detail.supplyState
    }

    init(_ row: SellsideProject) {
        internalName = row.internalName
        supplyState = row.supplyState
    }
}
