//
//  AxialMark.swift
//  Sellside Mobile
//

import SwiftUI

/// The Axial logo's four triangles, as a shape — the same geometry as the
/// app icon, so it stays sharp at any size and takes any fill. Keeps the
/// mark's proportions inside whatever frame it's given.
struct AxialMark: Shape {
    /// The artwork's bounds, in its own units.
    private static let viewBox = CGRect(x: 8.25, y: 12.97, width: 47.5, height: 37.2)

    /// One polygon per triangle, from the logo's SVG.
    private static let polygons: [[CGPoint]] = [
        [CGPoint(x: 38.2179, y: 24.7679), CGPoint(x: 31.9998, y: 14.997), CGPoint(x: 24.883, y: 26.1788),
         CGPoint(x: 29.0799, y: 32.7745), CGPoint(x: 31.9998, y: 37.3621), CGPoint(x: 39.1166, y: 26.1788)],
        [CGPoint(x: 40.3393, y: 28.1), CGPoint(x: 33.7379, y: 38.473), CGPoint(x: 33.2225, y: 39.2817),
         CGPoint(x: 39.518, y: 49.1737), CGPoint(x: 53.7499, y: 49.1737)],
        [CGPoint(x: 29.5699, y: 14.9745), CGPoint(x: 17.7537, y: 14.9745), CGPoint(x: 23.6626, y: 24.2595)],
        [CGPoint(x: 30.2622, y: 38.473), CGPoint(x: 23.6623, y: 28.1), CGPoint(x: 10.2501, y: 49.1737),
         CGPoint(x: 24.4821, y: 49.1737), CGPoint(x: 30.7775, y: 39.2817)],
    ]

    /// Width over height, for sizing the mark from one dimension.
    static let aspectRatio = viewBox.width / viewBox.height

    func path(in rect: CGRect) -> Path {
        let box = Self.viewBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        let origin = CGPoint(x: rect.midX - box.width * scale / 2, y: rect.midY - box.height * scale / 2)

        var path = Path()
        for polygon in Self.polygons {
            path.addLines(polygon.map {
                CGPoint(x: origin.x + ($0.x - box.minX) * scale, y: origin.y + ($0.y - box.minY) * scale)
            })
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    AxialMark()
        .fill(.white)
        .frame(width: 120, height: 120 / AxialMark.aspectRatio)
        .padding(40)
        .background(AxialColor.brandPrimary)
}
