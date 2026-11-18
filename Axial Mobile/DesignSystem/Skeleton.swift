//
//  Skeleton.swift
//  Axial Mobile
//

import SwiftUI

/// A placeholder block. Sized from the metrics of whatever it stands in for
/// so the layout doesn't jump when the real content lands.
struct SkeletonBox: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AxialColor.layer3)
            .frame(width: width, height: height)
    }
}

/// Stacked bars at a text style's line height, with a short last line so it
/// reads as wrapped text rather than a slab. Tracks Dynamic Type.
struct SkeletonText: View {
    var lines: Int = 2
    var style: UIFont.TextStyle = .body
    /// Width of the final bar; the rest fill the container.
    var lastLineWidth: CGFloat = 160

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize // re-renders on type-size change

    var body: some View {
        let font = UIFont.preferredFont(forTextStyle: style)
        let barHeight = font.capHeight + 4

        VStack(alignment: .leading, spacing: font.lineHeight - barHeight) {
            ForEach(0..<max(lines, 1), id: \.self) { index in
                SkeletonBox(
                    width: index == lines - 1 ? lastLineWidth : nil,
                    height: barHeight,
                    cornerRadius: barHeight / 3
                )
                .frame(maxWidth: index == lines - 1 ? nil : .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Sweeping highlight that marks content as still loading. Masked to the
    /// content's own shape, and a no-op under Reduce Motion.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

private struct Shimmer: ViewModifier {
    /// The sweep stays inside the greys. Placeholders rest on `layer3`, and
    /// the band lifts them one step to `layer2` — about a 4% shift — rather
    /// than flashing white across them. Fading through `layer2.opacity(0)`
    /// rather than `.clear` keeps the ramp neutral; `.clear` is transparent
    /// *black*, which greys the edges of the band on the way out.
    private static let band: [Gradient.Stop] = [
        .init(color: AxialColor.layer2.opacity(0), location: 0),
        .init(color: AxialColor.layer2, location: 0.5),
        .init(color: AxialColor.layer2.opacity(0), location: 1),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let bandWidth = width * 0.45
                        LinearGradient(stops: Self.band, startPoint: .leading, endPoint: .trailing)
                            .frame(width: bandWidth)
                            .offset(x: -bandWidth + phase * (width + bandWidth))
                    }
                    .allowsHitTesting(false)
                }
                .mask { content }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

#Preview("Skeletons") {
    VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonText(lines: 2, style: .title1, lastLineWidth: 200)
            SkeletonBox(width: 110, height: 26, cornerRadius: 13)
        }
        .shimmering()

        SkeletonText(lines: 3, style: .body)
            .shimmering()
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(AxialColor.canvas)
}
