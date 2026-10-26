//
//  SetupValidation.swift
//  Axial Mobile
//

import Foundation

/// Names one control in the wizard — the web's form-control path, e.g.
/// `companyBasics.internal_name`. Steps declare theirs as statics.
struct SetupFieldKey: Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}

/// Everything validation knows about the form at one moment: the message for
/// each invalid field, which fields are required, and each step's
/// required/completed count.
struct SetupValidation: Equatable {
    var errors: [SetupFieldKey: String] = [:]
    var required: Set<SetupFieldKey> = []
    var progress: [SetupStep: StepProgress] = [:]
    /// Errors the web shows before the field is touched (max-length).
    var immediate: Set<SetupFieldKey> = []
    /// EBITDA ≥ Revenue or another min/max failure — autosave leaves
    /// financials out while it holds (`financialsMinMax`).
    var financialsMinMaxError = false
    /// A KPI cell is invalid — autosave is suppressed entirely
    /// (`financialsKpisInvalid`).
    var kpisInvalid = false
    /// A URL field is invalid — autosave is suppressed (`hasDirtyUrlErrors`).
    var hasURLErrors = false

    var blocksAutosave: Bool { kpisInvalid || hasURLErrors }
}

/// Collects one step's validation. Mirrors `countRequiredFields`: a
/// required control counts toward M, and toward N when it's valid. A group
/// error marks the step invalid without changing the count.
struct StepValidationBuilder {
    let step: SetupStep
    private(set) var progress = StepProgress(required: 0, completed: 0)
    private(set) var errors: [SetupFieldKey: String] = [:]
    private(set) var required: Set<SetupFieldKey> = []

    init(step: SetupStep) { self.step = step }

    /// A required control. `error` is the message when it isn't satisfied —
    /// nil for the web's controls that only turn red with no text.
    mutating func require(_ field: SetupFieldKey, satisfied: Bool, error: String? = "Required") {
        required.insert(field)
        progress.required += 1
        if satisfied {
            progress.completed += 1
        } else {
            errors[field] = error ?? ""
        }
    }

    /// An optional control's own validator (a URL, an email list).
    mutating func check(_ field: SetupFieldKey, error: String?) {
        if let error { errors[field] = error }
    }

    /// An error on the group rather than any one control — the step is
    /// invalid, but the count doesn't move.
    mutating func groupError(_ field: SetupFieldKey, _ message: String?) {
        guard let message else { return }
        errors[field] = message
        progress.hasGroupError = true
    }
}

enum SetupValidator {
    static func validate(_ form: SetupForm, context: SetupContext) -> SetupValidation {
        var result = SetupValidation()
        for step in context.sequence {
            var builder = StepValidationBuilder(step: step)
            form.validate(step, context: context, into: &builder)
            result.progress[step] = builder.progress
            result.errors.merge(builder.errors) { $1 }
            result.required.formUnion(builder.required)
        }
        result.immediate = form.companyBasics.immediateErrors
        result.financialsMinMaxError = form.financials.periodic.hasMinMaxConflict
        result.kpisInvalid = form.financials.kpis.contains { $0.error != nil }
        result.hasURLErrors = [form.nda.linkedNdaUrl, form.cim.linkedCimUrl, form.cim.calendarLink]
            .contains { !URLRule.isValid($0) }
        return result
    }
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
