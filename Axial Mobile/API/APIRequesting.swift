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
}
