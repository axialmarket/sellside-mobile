//
//  APIEnvironment.swift
//  Axial Mobile
//

import Foundation

/// Resolves which API the app talks to.
///
/// Precedence:
/// 1. `UserDefaults` override (`api_base_url_override`) — the seam a future
///    debug-only environment switcher writes to (local API, elementals, …).
/// 2. `API_BASE_URL` from the active .xcconfig, passed through Info.plist.
struct APIEnvironment {
    static let overrideDefaultsKey = "api_base_url_override"

    let baseURL: URL

    static var current: APIEnvironment {
        if let override = UserDefaults.standard.string(forKey: overrideDefaultsKey),
           let url = URL(string: override) {
            return APIEnvironment(baseURL: url)
        }
        guard let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: value),
              url.scheme != nil, url.host() != nil else {
            fatalError("API_BASE_URL missing or invalid — check the active .xcconfig")
        }
        return APIEnvironment(baseURL: url)
    }

    /// Whether the API sits behind the VPN — `API_REQUIRES_VPN` in the active
    /// .xcconfig, set beside `API_BASE_URL` for an elemental. Only then is a
    /// gateway turn-away worth telling the user to connect
    /// (`APIError.isOffNetwork`). Absent means no: a production build that
    /// leaves it out never asks anyone to get on a VPN.
    static var requiresVPN: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "API_REQUIRES_VPN") as? String)?.uppercased() == "YES"
    }
}
