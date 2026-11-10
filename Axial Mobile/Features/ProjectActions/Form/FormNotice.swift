//
//  FormNotice.swift
//  Axial Mobile
//

import SwiftUI

/// `axl-inline-notification`: a tinted callout with an icon.
struct FormNotice: View {
    enum Style {
        case info, neutral, warning, error

        var tint: Color {
            switch self {
            case .info: AxialColor.brandPrimary
            case .neutral: AxialColor.textSecondary
            case .warning: TagPalette.yellow.foreground
            case .error: AxialColor.errorText
            }
        }

        var background: Color {
            switch self {
            case .info: AxialColor.brandSubtle
            case .neutral: AxialColor.layer3
            case .warning: TagPalette.yellow.background
            case .error: AxialColor.errorSubtle
            }
        }

        var systemImage: String {
            switch self {
            case .info, .neutral: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "exclamationmark.circle.fill"
            }
        }
    }

    let style: Style
    var title: String?
    var message: String?
    var bullets: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.tint)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                }
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(bullet)
                    }
                    .font(.footnote)
                }
            }
            .foregroundStyle(AxialColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
