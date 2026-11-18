//
//  AutoshareState.swift
//  Axial Mobile
//

import Foundation

/// SmartShare state on a project. Mirrors `TAutoshareState` in fe-app
/// intent.types.ts.
///
/// Matters here because while SmartShare is running, Axial is sharing the
/// teaser automatically and the recommended list is deliberately withheld —
/// see `ProjectDashboard.recommendedDeals`.
nonisolated enum AutoshareState: String, Decodable, Hashable, CaseIterable {
    case off
    case ready
    case enabled
    case expired
    case disabled
    case ineligible
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AutoshareState(rawValue: raw) ?? .unknown
    }
}
