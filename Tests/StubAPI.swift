//
//  StubAPI.swift
//  Tests
//

import Foundation
@testable import Axial_Mobile

/// Canned responses keyed by path, so store tests exercise real decoding and
/// real control flow without a network.
final class StubAPI: APIRequesting {
    /// JSON body per path, or an error to throw.
    enum Response {
        case json(String)
        case failure(Error)
    }

    var responses: [String: Response]
    private(set) var requestedPaths: [String] = []
    private(set) var postedBodies: [String: Data] = [:]
    /// Held open to test what happens while a request is still in flight.
    var gate: (() async -> Void)?

    init(responses: [String: Response] = [:]) {
        self.responses = responses
    }

    func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        try await respond(path)
    }

    func post<T: Decodable & Sendable>(_ path: String) async throws -> T {
        try await respond(path)
    }

    func post<T: Decodable & Sendable, U: Encodable>(_ path: String, body: U) async throws -> T {
        postedBodies[path] = try JSONEncoder().encode(body)
        return try await respond(path)
    }

    func patch<T: Decodable & Sendable, U: Encodable>(_ path: String, body: U) async throws -> T {
        postedBodies[path] = try JSONEncoder().encode(body)
        return try await respond(path)
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem], headers: [String: String]) async throws -> T {
        try await respond(path)
    }

    private(set) var deletedPaths: [String] = []

    func delete(_ path: String) async throws {
        requestedPaths.append(path)
        deletedPaths.append(path)
    }

    func upload<T: Decodable & Sendable>(_ path: String, form: MultipartForm) async throws -> T {
        try await respond(path)
    }

    /// Files by path or URL string.
    var downloads: [String: DownloadedFile] = [:]

    func download(_ path: String) async throws -> DownloadedFile {
        requestedPaths.append(path)
        guard let file = downloads[path] else { throw APIError.server(404, path: path, body: nil) }
        return file
    }

    func download(from url: URL) async throws -> DownloadedFile {
        try await download(url.absoluteString)
    }

    private func respond<T: Decodable & Sendable>(_ path: String) async throws -> T {
        requestedPaths.append(path)
        await gate?()
        switch responses[path] {
        case .json(let json):
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        case .failure(let error):
            throw error
        case nil:
            throw APIError.server(404, path: path, body: "StubAPI has no response")
        }
    }
}
