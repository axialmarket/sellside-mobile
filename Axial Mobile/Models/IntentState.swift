//
//  IntentState.swift
//  Axial Mobile
//

import Foundation

/// A project's lifecycle state. Mirrors `TIntentState` in fe-app
/// intent.model.ts — distinct from `SupplyState`, which is the sell-side
/// status shown in the UI. This one gates behaviour: the sharing settings
/// only make sense while a project is active.
nonisolated enum IntentState: String, Decodable, Hashable {
    case active
    case draft
    case archived
    case underLoi = "under_loi"
    case closed
    case onHold = "on_hold" // vestigial on the web, kept for parity
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IntentState(rawValue: raw) ?? .unknown
    }
}
