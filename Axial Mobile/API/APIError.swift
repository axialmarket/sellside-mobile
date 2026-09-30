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

    var errorDescription: String? {
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
