//
//  EpochDate.swift
//  Axial Mobile
//

import Foundation

/// Decodes the date fields on an intent.
///
/// They're numbers in fe-app's model and get handed straight to `new Date(n)`,
/// which reads them as **milliseconds** — so a naive `timeIntervalSince1970`
/// would land these dates in 1970. Strings are accepted too, since the wire
/// format isn't uniform across endpoints (`created_at` on a list row is one).
nonisolated enum EpochDate {
    static func decode<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>, forKey key: K
    ) -> Date? {
        if let milliseconds = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil {
            // 0 is the backend's "unset", not 1 January 1970.
            guard milliseconds > 0 else { return nil }
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        if let text = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
            return iso8601(text)
        }
        return nil
    }

    static func iso8601(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return fractional.date(from: text) ?? plain.date(from: text)
    }
}
