//
//  APIRequesting.swift
//  Axial Mobile
//

import Foundation

/// What a store needs from the network, so stores can be driven by a stub in
/// tests instead of `URLSession`. `APIClient` is the one production conformer.
protocol APIRequesting {
    func get<T: Decodable>(_ path: String) async throws -> T
    func post<T: Decodable>(_ path: String) async throws -> T
    func post<T: Decodable, U: Encodable>(_ path: String, body: U) async throws -> T
    func patch<T: Decodable, U: Encodable>(_ path: String, body: U) async throws -> T
    /// A GET with query parameters and extra headers (the taxonomy wants a
    /// versioned `Accept`).
    func get<T: Decodable>(_ path: String, query: [URLQueryItem], headers: [String: String]) async throws -> T
    func delete(_ path: String) async throws
    func upload<T: Decodable>(_ path: String, form: MultipartForm) async throws -> T
}

/// A `multipart/form-data` body: text fields and files, in order.
struct MultipartForm {
    enum Part {
        case field(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    var parts: [Part] = []
    let boundary = "axial-\(UUID().uuidString)"

    func encoded() -> Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            switch part {
            case let .field(name, value):
                body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            case let .file(name, filename, mimeType, data):
                body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
                body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
                body.append(data)
                body.append(Data("\r\n".utf8))
            }
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
