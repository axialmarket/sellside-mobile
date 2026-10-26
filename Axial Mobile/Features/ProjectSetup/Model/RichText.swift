//
//  RichText.swift
//  Axial Mobile
//

import Foundation

/// A rich-text field edited as plain text. The web edits description and
/// commentary in a TipTap editor and stores HTML; mobile edits paragraphs.
/// Untouched text writes back the original HTML byte for byte, so opening
/// setup on a phone never rewrites formatting the seller set on desktop —
/// and never shows up as a change in review.
struct RichTextValue: Equatable {
    var text: String
    private let originalHTML: String
    private let originalText: String

    init(html: String) {
        originalHTML = html
        originalText = RichText.plain(fromHTML: html)
        text = originalText
    }

    var html: String {
        text == originalText ? originalHTML : RichText.html(fromPlain: text)
    }

    /// `textContent.trim().length` — what the 300-character minimum counts.
    var visibleLength: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    var isEmpty: Bool { visibleLength == 0 }
}

enum RichText {
    static func plain(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }
        var text = html
        let replacements: [(String, String)] = [
            (#"<br\s*/?>"#, "\n"),
            (#"</p>\s*<p[^>]*>"#, "\n\n"),
            (#"</(li|h[1-6]|div)>"#, "\n"),
            (#"<li[^>]*>"#, "• "),
            (#"<[^>]+>"#, ""),
        ]
        for (pattern, replacement) in replacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Paragraphs on blank lines, `<br>` on single newlines.
    static func html(fromPlain text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.components(separatedBy: "\n\n").map { paragraph in
            let escaped = paragraph
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            return "<p>\(escaped)</p>"
        }.joined()
    }

    /// `stripHtmlTags` — the headline is plain text on the wire.
    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
    }
}
