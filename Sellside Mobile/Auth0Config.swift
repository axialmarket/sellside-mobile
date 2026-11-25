//
//  Auth0Config.swift
//  Sellside Mobile
//
//  Created by Matthew Sinex on 11/20/25.
//

import Foundation

struct Auth0Config: Codable {
    let clientId: String
    let domain: String

    static let shared: Auth0Config = {
        guard
            let url = Bundle.main.url(forResource: "Auth0", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        else {
            fatalError("❌ Failed to load Auth0.plist")
        }

        guard let clientId = plist["ClientId"] as? String
        else {
            fatalError("❌ Auth0.plist is missing ClientId")
        }
        // Fixed for the POC; make environment-driven alongside APIEnvironment
        // when the switcher lands (docs/CHALLENGES.md #1).
        let domain = "auth-development.axialmarket.com"

        return Auth0Config(clientId: clientId, domain: domain)
    }()
}
