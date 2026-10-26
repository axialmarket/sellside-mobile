//
//  SetupFormControls.swift
//  Axial Mobile
//

import SwiftUI

// The wizard's form kit. Each control reads its error from the session and
// reports its own blur, so the error rules live in one place and every field
// follows them: an error shows once the field has been touched and left, or
// once the member has tried to review (`revealValidationErrors`) — never on
// first render. That's Angular's `control.invalid && control.touched`, which
// `form-label.component.ts` and every web input use.

/// A segment card — `axl-step-segment`. Title with a required marker, an
/// optional description, and a 2pt red border while it owns a visible error.
struct SetupSegment<Content: View>: View {
    let title: String?
    var isRequired = false
    var description: String?
    /// True while validation is showing and a field inside is invalid.
    var hasError = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || description != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(AxialColor.textPrimary)
                            // An erroring segment always shows the marker,
                            // so the failure isn't carried by colour alone.
                            if isRequired || hasError {
                                RequiredMarker(isAttention: hasError)
                            }
                        }
                    }
                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(AxialColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(hasError ? 15 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hasError ? AxialColor.error : AxialColor.border, lineWidth: hasError ? 2 : 1)
        }
        .animation(.easeOut(duration: 0.2), value: hasError)
    }
}

/// The blue (red when invalid) asterisk after a required label.
struct RequiredMarker: View {
    var isAttention = false

    var body: some View {
        Text("*")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isAttention ? AxialColor.errorText : AxialColor.brandPrimary)
            .accessibilityLabel("Required")
    }
}

/// `axl-form-label`: the label, with `*` when the control is required.
struct SetupFieldLabel: View {
    let text: String
    var isRequired = false
    var isInvalid = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AxialColor.textPrimary)
            if isRequired {
                RequiredMarker(isAttention: isInvalid)
            }
        }
    }
}

/// An error line under a control: icon plus the web's message, verbatim.
struct SetupFieldError: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.footnote)
        .foregroundStyle(AxialColor.errorText)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Supporting copy under a control.
struct SetupHelperText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AxialColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A field's label, the control, and whichever of error or helper applies.
/// The error replaces the helper rather than stacking under it, as on the web.
struct SetupField<Control: View>: View {
    let label: String?
    let field: SetupFieldKey
    var helper: String?
    @ViewBuilder let control: Control

    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        let error = session.visibleError(for: field)
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                SetupFieldLabel(text: label, isRequired: session.isRequired(field), isInvalid: error != nil)
            }
            control
            if let error, !error.isEmpty {
                SetupFieldError(message: error)
            } else if let helper {
                SetupHelperText(text: helper)
            }
        }
        .animation(.easeOut(duration: 0.15), value: error)
        .id(field)
    }
}

/// The rounded input chrome every text-like control shares.
private struct InputChrome: ViewModifier {
    let isFocused: Bool
    let isInvalid: Bool
    var isMultiline = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, isMultiline ? 10 : 11)
            .background(AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isFocused || isInvalid ? 2 : 1)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var borderColor: Color {
        if isInvalid { return AxialColor.error }
        return isFocused ? AxialColor.brandPrimary : AxialColor.border
    }
}

/// Single-line text. Marks itself touched when focus leaves, which is when
/// Angular marks a control touched.
struct SetupTextField: View {
    let label: String?
    @Binding var text: String
    let field: SetupFieldKey
    var placeholder = ""
    var helper: String?
    var characterLimit: Int?
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var prefix: String?

    @Environment(ProjectSetupSession.self) private var session
    @FocusState private var isFocused: Bool

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            HStack(spacing: 6) {
                if let prefix {
                    Text(prefix).foregroundStyle(AxialColor.textSecondary)
                }
                TextField(placeholder, text: limited)
                    .focused($isFocused)
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .foregroundStyle(AxialColor.textPrimary)
                if let characterLimit, isFocused {
                    Text("\(text.count)/\(characterLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AxialColor.textPlaceholder)
                }
            }
            .modifier(InputChrome(isFocused: isFocused, isInvalid: session.visibleError(for: field) != nil))
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { session.touch(field) }
        }
    }

    private var limited: Binding<String> {
        Binding {
            text
        } set: { newValue in
            if let characterLimit, newValue.count > characterLimit {
                text = String(newValue.prefix(characterLimit))
            } else {
                text = newValue
            }
        }
    }
}

/// Multi-line text with an optional live character count.
struct SetupTextEditor: View {
    let label: String?
    @Binding var text: String
    let field: SetupFieldKey
    var placeholder = ""
    var helper: String?
    var characterLimit: Int?
    var minHeight: CGFloat = 120

    @Environment(ProjectSetupSession.self) private var session
    @FocusState private var isFocused: Bool

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(placeholder, text: limited, axis: .vertical)
                    .lineLimit(5...)
                    .focused($isFocused)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                    .foregroundStyle(AxialColor.textPrimary)
                    .modifier(InputChrome(isFocused: isFocused,
                                          isInvalid: session.visibleError(for: field) != nil,
                                          isMultiline: true))
                if let characterLimit {
                    Text("\(text.count)/\(characterLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(text.count >= characterLimit ? AxialColor.errorText : AxialColor.textPlaceholder)
                }
            }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { session.touch(field) }
        }
    }

    private var limited: Binding<String> {
        Binding {
            text
        } set: { newValue in
            if let characterLimit, newValue.count > characterLimit {
                text = String(newValue.prefix(characterLimit))
            } else {
                text = newValue
            }
        }
    }
}

/// A rich-text field (description, commentary) edited as paragraphs, with
/// the web's live "n of 300 character minimum." counter.
struct SetupRichTextEditor: View {
    let label: String?
    @Binding var value: RichTextValue
    let field: SetupFieldKey
    var placeholder = ""
    var counter: String?
    var counterIsValid = true
    var minHeight: CGFloat = 120

    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SetupTextEditor(label: label, text: $value.text, field: field, placeholder: placeholder,
                            minHeight: minHeight)
            if let counter, session.visibleError(for: field) == nil || session.visibleError(for: field)?.isEmpty == true {
                Text(counter)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(counterIsValid ? AxialColor.success : AxialColor.textSecondary)
                    .contentTransition(.numericText())
            }
        }
    }
}

/// A whole-number amount, typed as digits and shown grouped. Nil when empty.
struct SetupNumberField: View {
    let label: String?
    @Binding var value: Double?
    let field: SetupFieldKey
    var placeholder = ""
    var helper: String?
    var prefix: String? = "$"
    var suffix: String?
    var allowsDecimals = false
    var allowsNegative = false
    /// Entered in millions: a figure typed in whole dollars (≥ 10,000) is
    /// converted on blur, as the web's money input does.
    var millionsEntry = false

    @Environment(ProjectSetupSession.self) private var session
    @FocusState private var isFocused: Bool
    @State private var draft = ""

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            HStack(spacing: 6) {
                if let prefix {
                    Text(prefix).foregroundStyle(AxialColor.textSecondary)
                }
                TextField(placeholder, text: $draft)
                    .focused($isFocused)
                    .keyboardType(allowsDecimals || allowsNegative ? .numbersAndPunctuation : .numberPad)
                    .monospacedDigit()
                    .foregroundStyle(AxialColor.textPrimary)
                if let suffix {
                    Text(suffix).foregroundStyle(AxialColor.textSecondary)
                }
            }
            .modifier(InputChrome(isFocused: isFocused, isInvalid: session.visibleError(for: field) != nil))
        }
        .onAppear { draft = Self.format(value, decimals: allowsDecimals) }
        .onChange(of: value) { _, newValue in
            // Only reflect outside changes; while typing, the draft leads.
            if !isFocused { draft = Self.format(newValue, decimals: allowsDecimals) }
        }
        .onChange(of: draft) { _, newDraft in
            guard isFocused else { return }
            value = Self.parse(newDraft, decimals: allowsDecimals, negative: allowsNegative)
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused {
                if millionsEntry, let entered = value, abs(entered) >= 10_000 {
                    value = entered / 1_000_000
                }
                draft = Self.format(value, decimals: allowsDecimals)
                session.touch(field)
            }
        }
    }

    static func parse(_ text: String, decimals: Bool, negative: Bool) -> Double? {
        var allowed = CharacterSet.decimalDigits
        if decimals { allowed.insert(charactersIn: ".") }
        if negative { allowed.insert(charactersIn: "-") }
        let cleaned = String(text.unicodeScalars.filter(allowed.contains))
        guard !cleaned.isEmpty, cleaned != "-" else { return nil }
        return Double(cleaned)
    }

    static func format(_ value: Double?, decimals: Bool) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...(decimals ? 6 : 0))))
    }
}

/// One choice in a radio or checkbox list.
struct SetupChoice<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var detail: String?
    var systemImage: String?
    var id: Value { value }
}

/// `axl-radio-button radioStyle="button"`: bordered rows with a radio,
/// the selected one tinted.
struct SetupRadioGroup<Value: Hashable>: View {
    let label: String?
    let choices: [SetupChoice<Value>]
    @Binding var selection: Value?
    let field: SetupFieldKey
    var helper: String?

    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            VStack(spacing: 8) {
                ForEach(choices) { choice in
                    let isSelected = selection == choice.value
                    Button {
                        Haptics.selection()
                        selection = choice.value
                        session.touch(field)
                    } label: {
                        ChoiceRow(choice: choice, isSelected: isSelected, style: .radio,
                                  isInvalid: session.visibleError(for: field) != nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

/// Checkbox rows bound to a set.
struct SetupCheckboxGroup<Value: Hashable>: View {
    let label: String?
    let choices: [SetupChoice<Value>]
    @Binding var selection: Set<Value>
    let field: SetupFieldKey
    var helper: String?
    /// Hard cap; further boxes disable once reached.
    var limit: Int?

    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            VStack(spacing: 8) {
                ForEach(choices) { choice in
                    let isSelected = selection.contains(choice.value)
                    let isCapped = !isSelected && limit.map { selection.count >= $0 } == true
                    Button {
                        Haptics.selection()
                        if isSelected { selection.remove(choice.value) } else { selection.insert(choice.value) }
                        session.touch(field)
                    } label: {
                        ChoiceRow(choice: choice, isSelected: isSelected, style: .checkbox,
                                  isInvalid: session.visibleError(for: field) != nil)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCapped)
                    .opacity(isCapped ? 0.5 : 1)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

/// A plain on/off row — for a lone checkbox ("This is a confidential deal").
struct SetupToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AxialColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(AxialColor.brandPrimary)
    }
}

/// A single selection from a list too long for radios — opens a menu.
struct SetupMenuPicker<Value: Hashable>: View {
    let label: String?
    let choices: [SetupChoice<Value>]
    @Binding var selection: Value?
    let field: SetupFieldKey
    var placeholder = "Select"
    var helper: String?
    /// The web's `clearable` dropdowns.
    var allowsClear = false

    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            Menu {
                if allowsClear, selection != nil {
                    Button("Clear", systemImage: "xmark.circle", role: .destructive) { menuSelection.wrappedValue = nil }
                    Divider()
                }
                Picker(label ?? placeholder, selection: menuSelection) {
                    ForEach(choices) { choice in
                        Text(choice.label).tag(Optional(choice.value))
                    }
                }
            } label: {
                HStack {
                    Text(choices.first { $0.value == selection }?.label ?? placeholder)
                        .foregroundStyle(selection == nil ? AxialColor.textPlaceholder : AxialColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textSecondary)
                }
                .modifier(InputChrome(isFocused: false, isInvalid: session.visibleError(for: field) != nil))
            }
        }
    }

    private var menuSelection: Binding<Value?> {
        Binding {
            selection
        } set: {
            selection = $0
            session.touch(field)
        }
    }
}

/// A row that opens a full-screen picker (industries, locations) and shows
/// what's chosen as tags.
struct SetupPickerRow: View {
    let label: String?
    let field: SetupFieldKey
    let summary: [String]
    var placeholder = "Select"
    /// When the row shows a single chosen value as its text, not a placeholder.
    var hasValue = false
    var helper: String?
    let action: () -> Void

    @Environment(ProjectSetupSession.self) private var session

    var body: some View {
        SetupField(label: label, field: field, helper: helper) {
            Button(action: action) {
                HStack(alignment: .center, spacing: 8) {
                    if summary.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(hasValue ? AxialColor.textPrimary : AxialColor.textPlaceholder)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(summary, id: \.self) { item in
                                TagCapsule(text: item, palette: .blue)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AxialColor.textPlaceholder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .modifier(InputChrome(isFocused: false, isInvalid: session.visibleError(for: field) != nil))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Choice row

private struct ChoiceRow<Value: Hashable>: View {
    enum Style { case radio, checkbox }

    let choice: SetupChoice<Value>
    let isSelected: Bool
    let style: Style
    let isInvalid: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            indicator
                .padding(.top, 1)
            if let systemImage = choice.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textSecondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AxialColor.textPrimary)
                if let detail = choice.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AxialColor.brandSubtle : AxialColor.layer1, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var borderColor: Color {
        if isSelected { return AxialColor.brandPrimary }
        return isInvalid ? AxialColor.error : AxialColor.border
    }

    @ViewBuilder
    private var indicator: some View {
        switch style {
        case .radio:
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
        case .checkbox:
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
        }
    }
}
