//
//  ChartPalette.swift
//  Axial Mobile
//

import SwiftUI

/// Chart colours, from the web's design tokens. The third palette alongside
/// `AxialColor` and `TagPalette` — charts need more distinct hues than either.
enum ChartPalette {
    /// The positional shade ramp for funnel bars: lightest at the top,
    /// darkest at the bottom, one per row. `$color-blue-050` … `-900`, the
    /// list in fe-app `_funnel-shades.scss`.
    static let funnelShades: [Color] = [
        Color(hex: 0xECF1FE), // blue-050
        Color(hex: 0xD6E2FD), // blue-100
        Color(hex: 0xC5D6FC), // blue-150
        Color(hex: 0xB5CAFB), // blue-200
        Color(hex: 0xA5BEFA), // blue-250
        Color(hex: 0x94B3F9), // blue-300
        Color(hex: 0x749BF8), // blue-400
        Color(hex: 0x326CF4), // blue-500
        Color(hex: 0x2A5BCD), // blue-550
        Color(hex: 0x2249A6), // blue-600
        Color(hex: 0x1A387F), // blue-700
        Color(hex: 0x122758), // blue-800
        Color(hex: 0x0A1631), // blue-900
    ]

    /// Rows past the first six shades are dark enough to need white text.
    /// `$light-count`.
    static let lightFunnelShadeCount = 6

    static func funnelShade(at position: Int) -> Color {
        funnelShades[min(max(position, 0), funnelShades.count - 1)]
    }

    static func funnelCountColor(at position: Int) -> Color {
        position < lightFunnelShadeCount ? AxialColor.textPrimary : .white
    }
}

extension ChartSwatch {
    /// `$component-charts-informative-chart-NN`, light theme — the hexes
    /// member-breakdown.consts.ts hardcodes against those tokens.
    var color: Color {
        switch self {
        case .chart01: Color(hex: 0x749BF8)
        case .chart02: Color(hex: 0x39A292)
        case .chart03: Color(hex: 0x6EC8E3)
        case .chart04: Color(hex: 0xF2BD2E)
        case .chart05: Color(hex: 0x326CF4)
        case .chart06: Color(hex: 0x61B5A8)
        case .chart07: Color(hex: 0x2AAED6)
        case .chart09: Color(hex: 0x2249A6)
        case .chart10: Color(hex: 0x24685D)
        case .chart12: Color(hex: 0x7E6218)
        }
    }
}
