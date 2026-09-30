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
        body: Encodable?
    ) async throws -> URLRequest {
        
        // Build URL
        let url = APIEnvironment.current.baseURL.appendingPathComponent(path)
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Standard headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = await authService.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode body
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        return request
    }
    
    // MARK: - Public send() method
    
    func send<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        
        let request = try await authorizedRequest(path: path, method: method, body: body)
        logRequest(request)

        // Only genuine transport failures get wrapped — a catch-all here
        // would re-wrap APIError.unauthorized etc. and mask 401s.
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
        logResponse(http, data: data)

        switch http.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error, path: path)
            }

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
