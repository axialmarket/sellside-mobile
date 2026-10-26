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

    /// Partial update — project setup's saves and autosaves.
    func patch<T: Decodable, U: Encodable>(_ path: String, body: U) async throws -> T {
        try await send(path: path, method: "PATCH", body: body)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem], headers: [String: String]) async throws -> T {
        try await send(path: path, query: query, headers: headers)
    }

    func delete(_ path: String) async throws {
        try await sendIgnoringBody(path: path, method: "DELETE")
    }

    func upload<T: Decodable>(_ path: String, form: MultipartForm) async throws -> T {
        try await upload(path: path, form: form)
    }
}
