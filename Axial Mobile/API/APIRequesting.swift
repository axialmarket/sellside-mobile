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
    /// A file from the API, as bytes — deal documents.
    func download(_ path: String) async throws -> DownloadedFile
    /// A file from a URL the API handed out (a signed attachment link). Sent
    /// without our bearer token: it isn't ours to send to another host.
    func download(from url: URL) async throws -> DownloadedFile
}

/// A downloaded file. Held in memory; `DealFilePreview` writes it to a
/// temporary file only while it's open on screen.
struct DownloadedFile: Equatable {
    let data: Data
    /// From `Content-Disposition`, when the server names it.
    let filename: String?
    let mimeType: String?

    init(data: Data, filename: String? = nil, mimeType: String? = nil) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }

    /// `attachment; filename="NDA - Signed.pdf"` → `NDA - Signed.pdf`. Mirrors
    /// the web's `httpGetAndDownloadOrOpen`, which reads the same header.
    static func filename(fromContentDisposition header: String?) -> String? {
        guard let header else { return nil }
        if let range = header.range(of: #"filename\*=UTF-8''([^;]+)"#, options: .regularExpression) {
            let value = String(header[range]).replacingOccurrences(of: "filename*=UTF-8''", with: "")
            return value.removingPercentEncoding ?? value
        }
        guard let range = header.range(of: #"filename="?([^";]+)"?"#, options: .regularExpression) else { return nil }
        let value = header[range].replacingOccurrences(of: "filename=", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
        return value.isEmpty ? nil : value
    }
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
