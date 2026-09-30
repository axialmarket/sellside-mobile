//
//  IntentID.swift
//  Axial Mobile
//

import Foundation

/// Intent ids travel in two shapes: `GET /sellside-projects` returns a
/// hyphenated UUID in `public_id`, while `/api/intents/{id}` takes — and
/// echoes back — the hyphen-stripped form (fe-app strips it with
/// `removeHyphensFromId` before routing or requesting).
///
/// Normalizing on the way in means a cache key never depends on which
/// endpoint the id came from.
enum IntentID {
    static func normalized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: "")
    }
}
