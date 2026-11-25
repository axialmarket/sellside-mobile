//
//  DealTabBar.swift
//  Sellside Mobile
//

import SwiftUI

/// The deal screen's tabs, drawn like a segmented control but with each
/// segment sized to its label.
///
/// A segmented `Picker` gives every segment the same width, and at phone
/// width a quarter of the screen cut the web's "Company Profile" to
/// "Company Pr…" (see CHALLENGES #13). Here the labels keep their natural
/// widths and the spare room is shared out between them; the selected one
/// sits on a pill that slides to the next.
struct DealTabBar: View {
    let tabs: [DealDetailTab]
    @Binding var selection: DealDetailTab

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                segment(tab)
                if index < tabs.count - 1 {
                    Spacer(minLength: 2)
                }
            }
        }
        .padding(3)
        .background(AxialColor.inset, in: Capsule())
        .overlay(Capsule().strokeBorder(AxialColor.border))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deal-tabs")
    }

    private func segment(_ tab: DealDetailTab) -> some View {
        let isSelected = tab == selection
        return Button {
            guard !isSelected else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selection = tab }
        } label: {
            Text(tab.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? AxialColor.textPrimary : AxialColor.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background {
                    // Always present, so selection only moves the pill.
                    Capsule()
                        .fill(AxialColor.surface)
                        .overlay(Capsule().strokeBorder(AxialColor.border))
                        .matchedGeometryEffect(id: "pill", in: pill, isSource: isSelected)
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("deal-tab-\(tab.rawValue)")
    }
}

#Preview {
    @Previewable @State var tab = DealDetailTab.profile
    DealTabBar(tabs: DealDetailTab.allCases, selection: $tab)
        .padding()
        .background(AxialColor.canvas)
}
