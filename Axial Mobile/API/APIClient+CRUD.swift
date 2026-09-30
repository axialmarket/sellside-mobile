//
//  APIClient+CRUD.swift
//  Axial Mobile
//

import Foundation

extension APIClient: APIRequesting {
    // MARK: - Convenience methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path)
    }

    /// Bodyless POST — the shape the sellside status actions use. Matches
    /// fe-app, which posts `null` for actions that carry no payload.
    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "POST")
    }

    func post<T: Decodable, U: Encodable>(_ path: String, body: U) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }
}
