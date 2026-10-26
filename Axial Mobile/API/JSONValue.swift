//
//  JSONValue.swift
//  Axial Mobile
//

import Foundation

/// Any JSON value. Project setup edits a ~60-field intent of which mobile
/// models only part, so the wizard keeps the payload as a tree and writes its
/// fields into it, rather than round-tripping through a struct that would
/// drop whatever it doesn't know about.
enum JSONValue: Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value):
            // Whole numbers go out as integers — `2024`, not `2024.0`, which
            // the API's integer fields reject.
            if value.rounded() == value, abs(value) < 1e15 {
                try c.encode(Int64(value))
            } else {
                try c.encode(value)
            }
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }
}

// MARK: - Reading

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    /// Follows a dotted path — `"company.financials"`.
    subscript(path path: String) -> JSONValue? {
        path.split(separator: ".").reduce(Optional(self)) { $0?[String($1)] }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A non-empty, trimmed string, or nil.
    var text: String? {
        guard let value = string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    var number: Double? {
        switch self {
        case .number(let value): value
        // Decimal fields sometimes arrive quoted.
        case .string(let value): Double(value)
        default: nil
        }
    }

    var int: Int? { number.map { Int($0) } }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var isNull: Bool { self == .null }

    /// Strings out of an array, skipping anything else.
    var strings: [String] {
        array?.compactMap(\.string) ?? []
    }
}

// MARK: - Writing

extension JSONValue {
    /// Sets a value at a dotted path, creating intermediate objects. Writing
    /// into a non-object replaces it.
    mutating func set(_ value: JSONValue, at path: String) {
        let keys = path.split(separator: ".").map(String.init)
        set(value, at: keys[...])
    }

    private mutating func set(_ value: JSONValue, at keys: ArraySlice<String>) {
        guard let key = keys.first else {
            self = value
            return
        }
        var object = self.object ?? [:]
        var child = object[key] ?? .object([:])
        child.set(value, at: keys.dropFirst())
        object[key] = child
        self = .object(object)
    }

    /// Removes the keys named, at the top level only.
    func removingKeys(_ keys: some Sequence<String>) -> JSONValue {
        guard var object else { return self }
        for key in keys { object[key] = nil }
        return .object(object)
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(nilLiteral: ()) { self = .null }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }

    /// `.string`, or `.null` for nil — the API clears a field with `null`.
    static func string(orNull value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    static func number(orNull value: Double?) -> JSONValue {
        value.map(JSONValue.number) ?? .null
    }

    static func strings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }
}

// MARK: - Diff

extension JSONValue {
    /// What changed from `baseline` to `self`, as a partial patch: objects
    /// recurse key by key, anything else (arrays included) is sent whole when
    /// it differs. Keys only in the baseline are left out — the web never
    /// deletes by omission. `deepDiff` in project-setup-intent.utils.ts.
    func diff(from baseline: JSONValue?) -> JSONValue {
        guard let current = object else { return self }
        guard let base = baseline?.object else { return self }
        var patch: [String: JSONValue] = [:]
        for (key, value) in current {
            let old = base[key]
            if value.object != nil, old?.object != nil {
                let nested = value.diff(from: old)
                if nested.object?.isEmpty == false {
                    patch[key] = nested
                }
            } else if old != value {
                patch[key] = value
            }
        }
        return .object(patch)
    }

    /// True for `{}`.
    var isEmptyObject: Bool { object?.isEmpty == true }
}
