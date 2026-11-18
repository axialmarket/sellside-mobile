//
//  FixtureAPI.swift
//  Axial Mobile
//

#if DEBUG
import Foundation

/// Canned API responses for UI tests (`UITestMode`): one project in market
/// with a member in each list, shaped like the real payloads so they go
/// through the same decoding as production.
///
/// Paths without a fixture answer with the emptiest value the caller's type
/// accepts (`[]`, `{}`, then `null`), so a screen that asks for something
/// the tests don't care about shows its empty state rather than an error.
/// Writes succeed and change nothing; the tests here don't depend on them.
struct FixtureAPI: APIRequesting {
    static let projectId = "aaabbb"

    func get<T: Decodable & Sendable>(_ path: String) async throws -> T { try respond(path) }
    func post<T: Decodable & Sendable>(_ path: String) async throws -> T { try respond(path) }
    func post<T: Decodable & Sendable, U: Encodable>(_ path: String, body: U) async throws -> T { try respond(path) }
    func patch<T: Decodable & Sendable, U: Encodable>(_ path: String, body: U) async throws -> T { try respond(path) }
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem], headers: [String: String]) async throws -> T {
        try respond(path)
    }
    func delete(_ path: String) async throws {}
    func upload<T: Decodable & Sendable>(_ path: String, form: MultipartForm) async throws -> T { try respond(path) }

    func download(_ path: String) async throws -> DownloadedFile {
        DownloadedFile(data: Data("Fixture file".utf8), filename: "Fixture.txt", mimeType: "text/plain")
    }

    func download(from url: URL) async throws -> DownloadedFile {
        try await download(url.absoluteString)
    }

    private func respond<T: Decodable & Sendable>(_ path: String) throws -> T {
        let decoder = JSONDecoder()
        if let json = Self.responses[path] {
            return try decoder.decode(T.self, from: Data(json.utf8))
        }
        for fallback in ["[]", "{}", "null"] {
            if let value = try? decoder.decode(T.self, from: Data(fallback.utf8)) { return value }
        }
        throw APIError.server(404, path: path, body: "No UI test fixture for \(path)")
    }

    // MARK: - Fixtures

    static let responses: [String: String] = [
        "sellside-projects": """
        [{"public_id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "in_market",
          "intent_type": "sell_business", "sectors": [{"vertical": 1, "activity": 2, "name": "Industrials"}],
          "active_recommendations": 1, "unread_recommendations": 1, "active_deals": 1, "interested_members": 3,
          "assigned_to_user": {"public_id": "u-1", "first_name": "Sam", "last_name": "Seller"}},
         {"public_id": "ccc-ddd", "internal_name": "Project Atlas", "supply_state": "draft",
          "intent_type": "sell_business", "sectors": [], "active_recommendations": 0, "active_deals": 0,
          "interested_members": 0}]
        """,
        "intents/\(projectId)": """
        {"id": "aaa-bbb", "internal_name": "Project Neptune", "supply_state": "in_market",
         "intent_state": "active", "is_complete": true}
        """,
        "intents/\(projectId)/refer": #"{"short_url": "https://axial.link/neptune"}"#,
        "intents/sellside/\(projectId)/deals": """
        [{"public_id": "d1", "demand_account_public_id": "a1", "demand_account_name": "Bluewater Capital",
          "demand_user_name": "Jordan Reyes", "title": "Managing Director", "is_interested": true,
          "has_target_pursued": true, "supply_status": "target_signed_nda", "demand_account_code": "PE",
          "demand_account_city": "Austin", "demand_account_state_province": "TX", "demand_account_country": "US",
          "last_message": "Thanks, we'll review this week.", "last_message_from_full_name": "Jordan Reyes",
          "new_message_count": 1},
         {"public_id": "d2", "demand_account_public_id": "a2", "demand_account_name": "Harbor Point Partners",
          "demand_user_name": "Sam Okafor", "is_interested": true, "has_target_pursued": true,
          "supply_status": "sent_teaser", "demand_account_code": "FO"},
         {"public_id": "d3", "demand_account_public_id": "a3", "demand_account_name": "Summit Ridge",
          "is_interested": true, "supply_status": "target_requested_access", "demand_account_code": "HC"},
         {"public_id": "d4", "demand_account_public_id": "a4", "demand_account_name": "Cypress Holdings",
          "supply_status": "sent_teaser", "demand_account_code": "C"},
         {"public_id": "d5", "demand_account_public_id": "a5", "demand_account_name": "Oakline Capital",
          "supply_status": "not_shared", "demand_account_code": "PE"}]
        """,
        "users/me": """
        {"id": "u-1", "email": "sam.seller@example.com", "first_name": "Sam", "last_name": "Seller"}
        """,
    ]
}
#endif
