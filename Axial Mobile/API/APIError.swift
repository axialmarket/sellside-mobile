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
    case server(Int, body: String?)
    case decoding(Error)
    case transport(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .unauthorized: return "Unauthorized request."
        case .server(let code, let body):
            let detail = body.map { " — \($0.prefix(300))" } ?? ""
            return "Server error: \(code)\(detail)"
        case .decoding(let err): return "Decoding failed: \(err.localizedDescription)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        case .unknown: return "Unknown error."
        }
    }
}
