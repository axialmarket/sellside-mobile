//
//  APIClient.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import Foundation

@Observable
final class APIClient {
    let authService: AuthenticationService
    
    init(authService: AuthenticationService) {
        self.authService = authService
    }
    
    private func authorizedRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> URLRequest {
        var url = APIEnvironment.current.baseURL.appendingPathComponent(path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw APIError.invalidURL
            }
            components.queryItems = query
            guard let built = components.url else { throw APIError.invalidURL }
            url = built
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Standard headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let token = await authService.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Public send() method

    func send<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = try await authorizedRequest(path: path, method: method, query: query, headers: headers)
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data = try await perform(request, path: path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error, path: path)
        }
    }

    /// A request whose response body doesn't matter (DELETE).
    func sendIgnoringBody(path: String, method: String) async throws {
        let request = try await authorizedRequest(path: path, method: method)
        _ = try await perform(request, path: path)
    }

    /// `multipart/form-data` — document uploads.
    func upload<T: Decodable>(path: String, form: MultipartForm) async throws -> T {
        var request = try await authorizedRequest(path: path, method: "POST")
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encoded()
        let data = try await perform(request, path: path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error, path: path)
        }
    }

    /// Sends, maps the status, and returns the body. Only genuine transport
    /// failures get wrapped — a catch-all here would re-wrap
    /// APIError.unauthorized etc. and mask 401s.
    private func perform(_ request: URLRequest, path: String) async throws -> Data {
//        logRequest(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("⬅️ TRANSPORT ERROR \(request.httpMethod ?? "") \(request.url?.absoluteString ?? ""): \(error)")
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
//        logResponse(http, data: data)

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.server(
                http.statusCode, path: path, body: String(data: data, encoding: .utf8)
            )
        }
    }

    // MARK: - Console logging (POC only — replace with real telemetry, see docs/CHALLENGES.md #9)

    private func logRequest(_ request: URLRequest) {
        #if DEBUG
        var lines = ["➡️ \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")"]
        if let headers = request.allHTTPHeaderFields {
            let masked = headers.map { key, value in
                key == "Authorization" ? "\(key): Bearer …\(value.suffix(8))" : "\(key): \(value)"
            }
            lines.append("   headers: [\(masked.joined(separator: ", "))]")
        }
        if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            lines.append("   payload: \(text)")
        }
        print(lines.joined(separator: "\n"))
        #endif
    }

    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        #if DEBUG
        let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, non-UTF8>"
        print("""
        ⬅️ \(response.statusCode) \(response.url?.absoluteString ?? "?")
           response: \(body.prefix(2000))
        """)
        #endif
    }
}
