//
//  TokenTextView.swift
//  Axial Mobile
//

import SwiftUI
import UIKit

/// Lets a button outside the editor insert a tag at the cursor. Hand the
/// same instance to `TokenTextView` and call `insert(_:)`.
@MainActor
final class TokenTextController {
    fileprivate weak var coordinator: TokenTextView.Coordinator?

    func insert(_ tag: MergeTag) {
        coordinator?.insert(tag)
    }
}

/// A multi-line editor that shows merge tags as chips — the mobile form of
/// the web's `axl-token-textarea`, which draws each token as an image.
///
/// `text` stays plain: every chip reads back as its `{key}`, so what's saved
/// is exactly what the web saves. A chip is one character to the text view,
/// so backspace removes it whole and the cursor can't land inside it.
///
/// UIKit rather than SwiftUI's `TextEditor`, which can style runs but can't
/// hold an inline attachment.
struct TokenTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var controller: TokenTextController?
    var minHeight: CGFloat = 120
    var accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        // The surrounding chrome pads the text, as it does for a TextField.
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.typingAttributes = Coordinator.textAttributes
        view.accessibilityIdentifier = accessibilityIdentifier
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textView = view
        context.coordinator.show(text)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller?.coordinator = coordinator
        // Only rebuild for a change from outside (a load, a reset); the
        // view's own edits have already been reported up.
        if text != coordinator.reportedText {
            coordinator.show(text)
        }
        if isFocused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minHeight, fitting.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TokenTextView
        weak var textView: UITextView?
        /// The last text this view reported, to tell its own edits from a
        /// change made elsewhere.
        var reportedText = ""

        init(_ parent: TokenTextView) {
            self.parent = parent
        }

        static var font: UIFont { .preferredFont(forTextStyle: .body) }

        static var textAttributes: [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: UIColor(AxialColor.textPrimary)]
        }

        func show(_ text: String) {
            guard let textView else { return }
            let selection = textView.selectedRange
            textView.attributedText = Self.attributed(MergeTag.segments(in: text))
            textView.typingAttributes = Self.textAttributes
            if selection.upperBound <= textView.textStorage.length {
                textView.selectedRange = selection
            }
            reportedText = text
        }

        /// At the cursor, or at the end when the editor isn't focused. A
        /// space goes in first when the tag would otherwise touch a word.
        func insert(_ tag: MergeTag) {
            guard let textView else { return }
            let storage = textView.textStorage
            let range = textView.isFirstResponder
                ? textView.selectedRange
                : NSRange(location: storage.length, length: 0)
            let insertion = NSMutableAttributedString()
            if range.location > 0 {
                let previous = (storage.string as NSString).substring(with: NSRange(location: range.location - 1, length: 1))
                if previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                    insertion.append(NSAttributedString(string: " ", attributes: Self.textAttributes))
                }
            }
            insertion.append(Self.chip(for: tag))
            storage.replaceCharacters(in: range, with: insertion)
            textView.selectedRange = NSRange(location: range.location + insertion.length, length: 0)
            textView.typingAttributes = Self.textAttributes
            report()
        }

        func textViewDidChange(_ textView: UITextView) {
            report()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        /// Typing right after a chip would otherwise carry its attachment
        /// attributes into the new text.
        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.typingAttributes = Self.textAttributes
        }

        private func report() {
            guard let textView else { return }
            let text = Self.plainText(textView.attributedText)
            reportedText = text
            if parent.text != text { parent.text = text }
        }

        // MARK: Conversion

        static func attributed(_ segments: [MergeTag.Segment]) -> NSAttributedString {
            let result = NSMutableAttributedString()
            for segment in segments {
                switch segment {
                case .text(let text): result.append(NSAttributedString(string: text, attributes: textAttributes))
                case .tag(let tag): result.append(chip(for: tag))
                }
            }
            return result
        }

        static func plainText(_ attributed: NSAttributedString) -> String {
            var segments: [MergeTag.Segment] = []
            let string = attributed.string as NSString
            attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                if let chip = value as? TokenAttachment {
                    segments.append(.tag(chip.tag))
                } else if value == nil {
                    segments.append(.text(string.substring(with: range)))
                }
            }
            return MergeTag.message(from: segments)
        }

        static func chip(for tag: MergeTag) -> NSAttributedString {
            let attachment = TokenAttachment(tag: tag, font: font)
            let chip = NSMutableAttributedString(attachment: attachment)
            chip.addAttributes(textAttributes, range: NSRange(location: 0, length: chip.length))
            return chip
        }
    }
}

/// One tag, drawn as a brand-tinted capsule sitting on the text's baseline.
private final class TokenAttachment: NSTextAttachment {
    let tag: MergeTag

    init(tag: MergeTag, font: UIFont) {
        self.tag = tag
        super.init(data: nil, ofType: nil)

        let labelFont = UIFont.systemFont(ofSize: font.pointSize * 0.85, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor(AxialColor.brandPrimary),
        ]
        let textSize = (tag.label as NSString).size(withAttributes: attributes)
        let padding = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        let size = CGSize(width: ceil(textSize.width) + padding.left + padding.right,
                          height: ceil(textSize.height) + padding.top + padding.bottom)

        image = UIGraphicsImageRenderer(size: size).image { _ in
            let shape = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            UIColor(AxialColor.brandSubtle).setFill()
            shape.fill()
            (tag.label as NSString).draw(at: CGPoint(x: padding.left, y: padding.top), withAttributes: attributes)
        }
        image?.accessibilityLabel = tag.spokenLabel
        // Centred on the capitals rather than sat on the baseline, so it
        // lines up with the words beside it.
        bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
