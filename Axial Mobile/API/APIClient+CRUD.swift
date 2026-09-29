//
//  APIClient+CRUD.swift
//  Axial Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import Foundation

extension APIClient {
    // MARK: - Convenience methods
    
    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path)
    }
    
    func post<T: Decodable, U: Encodable>(_ path: String, body: U) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }
}
