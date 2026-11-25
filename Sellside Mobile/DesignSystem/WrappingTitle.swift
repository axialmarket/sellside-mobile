//
//  WrappingTitle.swift
//  Sellside Mobile
//

import SwiftUI

/// A title that flows around something pinned to its top-trailing corner —
/// a status pill, typically — so the first lines stop short of it and the rest
/// run the full width.
///
/// SwiftUI has no float: a `Text` is laid out in one rectangle, so an `HStack`
/// gives the title a narrow column for *every* line, wasting the space under
/// the badge. The way around it is to lay the words out individually, which is
/// what `WordFlowLayout` does.
///
/// The words are separate views, so the whole thing is collapsed into a single
/// accessibility element carrying the real string — otherwise VoiceOver would
/// read a title one word at a time. The badge is deliberately *not* a subview;
/// it's overlaid separately so it keeps its own element and its tap action.
struct WrappingTitle: View {
    let text: String
    /// Space to keep clear at the top-trailing corner.
    let reserved: CGSize
    var font: Font = .title.weight(.bold)
    /// Width of a space in the title's font, so wrapped words sit naturally.
    var wordSpacing: CGFloat
    var lineLimit: Int?

    private var words: [Substring] {
        text.split(separator: " ", omittingEmptySubsequences: true)
    }

    var body: some View {
        WordFlowLayout(
            reserved: reserved,
            wordSpacing: wordSpacing,
            lineLimit: lineLimit
        ) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(font)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Flows its subviews left-to-right, wrapping, while keeping a rectangle at
/// the top-trailing corner clear.
struct WordFlowLayout: Layout {
    var reserved: CGSize = .zero
    var wordSpacing: CGFloat = 8
    var lineSpacing: CGFloat = 2
    /// Lines beyond this are dropped. Nil means no limit.
    var lineLimit: Int?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let result = solve(subviews: subviews, width: width)
        return CGSize(width: width, height: max(result.height, reserved.height))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let result = solve(subviews: subviews, width: bounds.width)
        for placement in result.placements {
            subviews[placement.index].place(
                at: CGPoint(
                    x: bounds.minX + placement.frame.minX,
                    y: bounds.minY + placement.frame.minY
                ),
                proposal: ProposedViewSize(placement.frame.size)
            )
        }
        // Anything past the line limit is parked off-screen rather than left
        // at the origin, where it would pile up on the first word.
        for index in result.dropped {
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY + 10_000),
                proposal: .zero
            )
        }
    }

    // MARK: - Solving

    private struct Placement {
        let index: Int
        let frame: CGRect
    }

    private struct Result {
        var placements: [Placement] = []
        var dropped: [Int] = []
        var height: CGFloat = 0
    }

    private func solve(subviews: Subviews, width: CGFloat) -> Result {
        guard width > 0, !subviews.isEmpty else { return Result() }

        // A word laid out with no width constraint occupies exactly one line —
        // the yardstick for noticing when one had to break internally.
        let singleLine = subviews
            .map { $0.sizeThatFits(.unspecified).height }
            .min() ?? 0

        var result = Result()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var line = 0

        /// The badge sits top-trailing, so lines starting above its bottom
        /// edge are short and everything below runs full width.
        func available(at y: CGFloat) -> CGFloat {
            y < reserved.height ? max(width - reserved.width, 0) : width
        }

        func startNewLine() -> Bool {
            y += lineHeight + lineSpacing
            x = 0
            lineHeight = 0
            line += 1
            return lineLimit.map { line < $0 } ?? true
        }

        for index in subviews.indices {
            var size = subviews[index]
                .sizeThatFits(ProposedViewSize(width: available(at: y), height: nil))

            if x > 0, x + wordSpacing + size.width > available(at: y) {
                guard startNewLine() else {
                    result.dropped.append(contentsOf: subviews.indices[index...])
                    break
                }
                size = subviews[index]
                    .sizeThatFits(ProposedViewSize(width: available(at: y), height: nil))
            }

            let originX = x == 0 ? 0 : x + wordSpacing
            result.placements.append(
                Placement(index: index, frame: CGRect(origin: CGPoint(x: originX, y: y), size: size))
            )
            x = originX + size.width
            lineHeight = max(lineHeight, size.height)

            // A word too long for one line wraps inside its own Text — an email
            // address, say. It has already consumed several lines, so nothing
            // may sit beside it.
            if size.height > singleLine * 1.5 {
                line += Int((size.height / max(singleLine, 1)).rounded()) - 1
                guard startNewLine() else {
                    result.dropped.append(contentsOf: subviews.indices[(index + 1)...])
                    break
                }
            }
        }

        result.height = y + lineHeight
        return result
    }
}
