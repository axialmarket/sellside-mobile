//
//  FormValidation.swift
//  Sellside Mobile
//

import Foundation
import Observation

/// Names one control in a form — e.g. `followUp.message`.
struct FormFieldKey: Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}

/// A form's errors and when to show them. The form kit reads this from the
/// environment, so every control follows the web's rule: an error shows once
/// the field has been touched and left, or once the member has tried to
/// submit (`revealValidationErrors`) — never on first render. That's
/// Angular's `control.invalid && control.touched`.
@Observable
final class FormValidation {
    /// Field → message. An empty message draws the invalid state with no
    /// sentence, as the web does for most required fields.
    var errors: [FormFieldKey: String] = [:]
    var required: Set<FormFieldKey> = []
    private(set) var touched: Set<FormFieldKey> = []
    private(set) var showsAll = false

    var isValid: Bool { errors.isEmpty }

    func visibleError(for field: FormFieldKey) -> String? {
        guard showsAll || touched.contains(field) else { return nil }
        return errors[field]
    }

    func isRequired(_ field: FormFieldKey) -> Bool { required.contains(field) }

    func touch(_ field: FormFieldKey) {
        if !touched.contains(field) { touched.insert(field) }
    }

    /// Submit was tapped: show everything.
    func revealAll() { showsAll = true }
}

/// `validateUrl()` (question-control.validator-fns.ts): blank passes;
/// otherwise a host with a TLD, optional scheme, port and path, and no
/// whitespace anywhere.
enum URLRule {
    static func isValid(_ value: String) -> Bool {
        if value.isEmpty { return true }
        if value.contains(where: \.isWhitespace) { return false }
        let pattern = #"^(https?://)?([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(:\d{1,5})?(/[^\s]*)?$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `sanitizeUrl`: prefixes `https://` when there's no scheme.
    static func sanitized(_ value: String) -> String {
        let lower = value.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://") ? value : "https://\(value)"
    }
}
