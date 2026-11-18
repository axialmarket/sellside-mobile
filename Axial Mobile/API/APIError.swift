//
//  APIError.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case server(Int, path: String, body: String?)
    case decoding(Error, path: String)
    case transport(Error)
    case unknown

    /// The network gate turned the request away before the API saw it: 503,
    /// or 403 with Envoy's "RBAC: access denied". Off the VPN, that's what an
    /// elemental answers (CHALLENGES #8).
    var isGatewayRejection: Bool {
        guard case .server(let code, _, let body) = self else { return false }
        return code == 503 || (code == 403 && body?.contains("RBAC") == true)
    }

    /// A gateway turn-away from an API that's behind the VPN — the one case
    /// where telling the user to connect is the answer. Against a public
    /// API (`API_REQUIRES_VPN` unset) a 503 is just the service being down.
    func isOffNetwork(requiresVPN: Bool = APIEnvironment.requiresVPN) -> Bool {
        requiresVPN && isGatewayRejection
    }

    static let offNetworkMessage = "Axial can't be reached from this network. Turn on the VPN on this device, then try again."

    var errorDescription: String? {
        if isOffNetwork() { return Self.offNetworkMessage }
        if case .server(503, _, _) = self { return "Axial is temporarily unavailable. Please try again shortly." }
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .unauthorized: return "Unauthorized request."
        // The path matters: a screen can have several requests in flight, and
        // "Server error: 404" alone doesn't say which one missed.
        case .server(let code, let path, let body):
            let detail = body.map { " — \($0.prefix(300))" } ?? ""
            return "Server error: \(code) on \(path)\(detail)"
        case .decoding(let err, let path):
            return "Decoding failed for \(path): \(err.localizedDescription)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        case .unknown: return "Unknown error."
        }
    }
}
