//
//  FormControls.swift
//  Axial Mobile
//

import SwiftUI

// The form kit for the focused action sheets. Each control reads its error
// from the environment's `FormValidation` and reports its own blur, so the error rules live in one place and every field
// follows them: an error shows once the field has been touched and left, or
// once the member has tried to submit (`revealValidationErrors`) — never on
// first render. That's Angular's `control.invalid && control.touched`, which
// `form-label.component.ts` and every web input use.

/// A segment card — `axl-step-segment`. Title with a required marker, an
/// optional description, and a 2pt red border while it owns a visible error.
struct FormSegment<Content: View>: View {
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
struct FormFieldLabel: View {
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
struct FormFieldError: View {
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
struct FormHelperText: View {
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
struct FormField<Control: View>: View {
    let label: String?
    let field: FormFieldKey
    var helper: String?
    @ViewBuilder let control: Control

    @Environment(FormValidation.self) private var validation

    var body: some View {
        let error = validation.visibleError(for: field)
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                FormFieldLabel(text: label, isRequired: validation.isRequired(field), isInvalid: error != nil)
            }
            control
            if let error, !error.isEmpty {
                FormFieldError(message: error)
            } else if let helper {
                FormHelperText(text: helper)
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

/// Multi-line text with an optional live character count.
struct FormTextEditor: View {
    let label: String?
    @Binding var text: String
    let field: FormFieldKey
    var placeholder = ""
    var helper: String?
    var characterLimit: Int?
    var minHeight: CGFloat = 120

    @Environment(FormValidation.self) private var validation
    @FocusState private var isFocused: Bool

    var body: some View {
        FormField(label: label, field: field, helper: helper) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(placeholder, text: limited, axis: .vertical)
                    .lineLimit(5...)
                    .focused($isFocused)
                    .frame(minHeight: minHeight, alignment: .topLeading)
                    .foregroundStyle(AxialColor.textPrimary)
                    .modifier(InputChrome(isFocused: isFocused,
                                          isInvalid: validation.visibleError(for: field) != nil,
                                          isMultiline: true))
                if let characterLimit {
                    Text("\(text.count)/\(characterLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(text.count >= characterLimit ? AxialColor.errorText : AxialColor.textPlaceholder)
                }
            }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { validation.touch(field) }
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

/// One choice in a radio or checkbox list.
struct FormChoice<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var detail: String?
    var systemImage: String?
    var id: Value { value }
}

/// `axl-radio-button radioStyle="button"`: bordered rows with a radio,
/// the selected one tinted.
struct FormRadioGroup<Value: Hashable>: View {
    let label: String?
    let choices: [FormChoice<Value>]
    @Binding var selection: Value?
    let field: FormFieldKey
    var helper: String?

    @Environment(FormValidation.self) private var validation

    var body: some View {
        FormField(label: label, field: field, helper: helper) {
            VStack(spacing: 8) {
                ForEach(choices) { choice in
                    let isSelected = selection == choice.value
                    Button {
                        Haptics.selection()
                        selection = choice.value
                        validation.touch(field)
                    } label: {
                        ChoiceRow(choice: choice, isSelected: isSelected,
                                  isInvalid: validation.visibleError(for: field) != nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

/// A row that opens a full-screen picker (industries, locations) and shows
/// what's chosen as tags.
struct FormPickerRow: View {
    let label: String?
    let field: FormFieldKey
    let summary: [String]
    var placeholder = "Select"
    /// When the row shows a single chosen value as its text, not a placeholder.
    var hasValue = false
    var helper: String?
    let action: () -> Void

    @Environment(FormValidation.self) private var validation

    var body: some View {
        FormField(label: label, field: field, helper: helper) {
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
                .modifier(InputChrome(isFocused: false, isInvalid: validation.visibleError(for: field) != nil))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Choice row

private struct ChoiceRow<Value: Hashable>: View {
    let choice: FormChoice<Value>
    let isSelected: Bool
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

    private var indicator: some View {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(isSelected ? AxialColor.brandPrimary : AxialColor.textPlaceholder)
    }
}
