//
//  APIEnvironmentTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Sellside_Mobile

struct APIEnvironmentTests {

    @Test func userDefaultsOverrideWins() {
        UserDefaults.standard.set("https://example.com/api", forKey: APIEnvironment.overrideDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: APIEnvironment.overrideDefaultsKey) }

        #expect(APIEnvironment.current.baseURL.absoluteString == "https://example.com/api")
    }

    @Test func fallsBackToInfoPlist() {
        UserDefaults.standard.removeObject(forKey: APIEnvironment.overrideDefaultsKey)

        let url = APIEnvironment.current.baseURL
        #expect(url.scheme == "https")
        #expect(url.host()?.isEmpty == false)
    }
}
