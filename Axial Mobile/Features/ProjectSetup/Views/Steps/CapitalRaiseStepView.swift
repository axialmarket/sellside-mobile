//
//  CapitalRaiseStepView.swift
//  Axial Mobile
//

import SwiftUI

/// Capital Raise — capital-raise-section.html: type of capital, type of
/// debt (only with debt), use of funds, and the range (max first).
struct CapitalRaiseStepView: View {
    @Environment(ProjectSetupSession.self) private var session
    private typealias F = CapitalRaiseForm.Field

    var body: some View {
        @Bindable var session = session
        let form = $session.form.capitalRaise
        let capitalType = Binding<String?>(
            get: { form.wrappedValue.capitalType },
            set: { form.wrappedValue.setCapitalType($0) }
        )

        SetupSegment(title: "Type of Capital", hasError: session.segmentHasError([F.capitalType])) {
            SetupRadioGroup(label: "What type of capital are you seeking?", choices: CapitalOptions.capitalTypes,
                            selection: capitalType, field: F.capitalType)
        }

        if form.wrappedValue.includesDebt {
            SetupSegment(title: "Type of Debt", hasError: session.segmentHasError([F.debtTypes])) {
                SetupField(label: "What type(s) of debt? Choose up to 5.", field: F.debtTypes) {
                    DebtTypeList(value: form.debtTypes)
                }
                if form.wrappedValue.debtTypes.filter({ $0 != DebtTypes.openToAny }).count >= CapitalRaiseForm.debtMax {
                    SetupNotice(style: .info,
                                message: "You cannot select more than 5 debt types. If you're open to more, please select \"Open to any type of debt\".")
                }
            }
            .transition(.opacity)
        }

        SetupSegment(title: "Intended Use of Funds", hasError: session.segmentHasError([F.useOfFunds])) {
            SetupCheckboxGroup(label: "What is the company's intended use of funds?", choices: CapitalOptions.useOfFunds,
                               selection: Binding(
                                   get: { Set(form.wrappedValue.useOfFunds) },
                                   set: { new in
                                       form.wrappedValue.useOfFunds = CapitalOptions.useOfFunds.map(\.value).filter(new.contains)
                                   }),
                               field: F.useOfFunds)
            SetupNotice(style: .neutral,
                        message: "This information is used to improve matching quality and will not be disclosed.")
        }

        SetupSegment(title: "Capital Range", hasError: session.segmentHasError([F.maxRange, F.minRange])) {
            SetupNumberField(label: "What is the total amount of capital you are seeking in millions?",
                             value: form.maxRange, field: F.maxRange, placeholder: "0.0",
                             helper: "For example, 250,000 would be 0.25M.", suffix: "M",
                             allowsDecimals: true, allowsNegative: true, millionsEntry: true)
            SetupNumberField(label: "What is the minimum check size you are willing to entertain from one party?",
                             value: form.minRange, field: F.minRange, placeholder: "0.0", suffix: "M",
                             allowsDecimals: true, allowsNegative: true, millionsEntry: true)
        }
    }
}

/// `nested-checkbox-list` for debt: parents expand, leaves check, a cap of
/// five, and the exclusive "Open to any type of debt".
private struct DebtTypeList: View {
    @Binding var value: [String]
    @State private var expanded: Set<String> = []

    private var leaves: Set<String> { DebtTypes.checkedLeaves(value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DebtTypes.tree) { node in
                rows(node, depth: 0)
            }
        }
        .onAppear {
            // A parent with anything checked under it opens.
            for node in DebtTypes.tree where node.leaves.contains(where: leaves.contains) && !node.children.isEmpty {
                expanded.insert(node.key)
                for child in node.children where child.leaves.contains(where: leaves.contains) && !child.children.isEmpty {
                    expanded.insert(child.key)
                }
            }
        }
    }

    private func rows(_ node: DebtTypes.Node, depth: Int) -> AnyView {
        if node.children.isEmpty {
            let isOn = leaves.contains(node.key)
            let capped = !isOn && node.key != DebtTypes.openToAny
                && leaves.subtracting([DebtTypes.openToAny]).count >= CapitalRaiseForm.debtMax
            return AnyView(
                Button {
                    Haptics.selection()
                    value = DebtTypes.value(from: DebtTypes.toggle(node.key, in: leaves))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isOn ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
                        Text(node.label)
                            .font(.subheadline)
                            .foregroundStyle(AxialColor.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, CGFloat(depth) * 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(capped)
                .opacity(capped ? 0.45 : 1)
            )
        }
        let isOpen = expanded.contains(node.key)
        let hasChecked = node.leaves.contains(where: leaves.contains)
        return AnyView(VStack(alignment: .leading, spacing: 2) {
            Button {
                // Can't fold away a checked descendant.
                guard !hasChecked || !isOpen else { return }
                withAnimation(.snappy) {
                    if isOpen { expanded.remove(node.key) } else { expanded.insert(node.key) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(AxialColor.textSecondary)
                    Text(node.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AxialColor.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.leading, CGFloat(depth) * 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                ForEach(node.children) { child in
                    rows(child, depth: depth + 1)
                }
            }
        })
    }
}
