//
//  ProjectDetail.swift
//  Axial Mobile
//

import Foundation

/// One project from `GET /api/intents/{id}`. Mirrors fe-app's `IIntentData`
/// (intent.model.ts) — a ~60-field payload — decoding only what the mobile
/// dashboard renders. Lenient by design: everything except `id` and
/// `internal_name` tolerates absence.
///
/// This is also the shape every *mutation* answers with: `PATCH
/// /api/intents/{id}` returns `{ intent: IIntentData, … }` and the
/// status-change POSTs return the intent itself. Those responses go through
/// `ProjectDetailStore.apply(_:)` rather than triggering a re-fetch.
struct ProjectDetail: Decodable, Identifiable, Equatable {
    /// Always hyphen-stripped — see `IntentID`.
    let id: String
    let internalName: String
    let supplyState: SupplyState

    enum CodingKeys: String, CodingKey {
        case id
        case internalName = "internal_name"
        case supplyState = "supply_state"
    }

    init(id: String, internalName: String, supplyState: SupplyState = .unknown) {
        self.id = IntentID.normalized(id)
        self.internalName = internalName
        self.supplyState = supplyState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = IntentID.normalized(try c.decode(String.self, forKey: .id))
        internalName = try c.decode(String.self, forKey: .internalName)
        // Typed `IntentSupplyState | null` on the web (null on buyside intents).
        supplyState = try c.decodeIfPresent(SupplyState.self, forKey: .supplyState) ?? .unknown
    }
}
