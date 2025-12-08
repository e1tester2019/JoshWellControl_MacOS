//
//  NumericTextField.swift
//  Josh Well Control for Mac
//
//  A text field for numeric input that doesn't apply formatting while typing.
//  Formatting is only applied when the field loses focus.
//

import SwiftUI

/// A text field optimized for numeric entry that doesn't interrupt typing with live formatting
struct NumericTextField: View {
    let placeholder: String
    @Binding var value: Double
    var fractionDigits: Int = 2
    var onCommit: (() -> Void)? = nil

    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $textValue)
            .focused($isFocused)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .onChange(of: isFocused) { _, focused in
                if focused {
                    // When gaining focus, show raw number without formatting
                    if value == 0 {
                        textValue = ""
                    } else {
                        // Show without thousand separators for easy editing
                        textValue = formatForEditing(value)
                    }
                } else {
                    // When losing focus, parse and update value
                    if let parsed = parseNumber(textValue) {
                        value = parsed
                        onCommit?()
                    }
                    // Update display to formatted value
                    textValue = formatForDisplay(value)
                }
            }
            .onAppear {
                textValue = formatForDisplay(value)
            }
            .onChange(of: value) { _, newValue in
                // Only update if not focused (external change)
                if !isFocused {
                    textValue = formatForDisplay(newValue)
                }
            }
    }

    private func formatForEditing(_ val: Double) -> String {
        if val == floor(val) && fractionDigits == 0 {
            return String(format: "%.0f", val)
        }
        // Remove trailing zeros for cleaner editing
        let formatted = String(format: "%.\(fractionDigits)f", val)
        return trimTrailingZeros(formatted)
    }

    private func formatForDisplay(_ val: Double) -> String {
        if val == 0 && fractionDigits > 0 {
            return String(format: "%.2f", val)
        }
        return String(format: "%.\(fractionDigits)f", val)
    }

    private func trimTrailingZeros(_ str: String) -> String {
        guard str.contains(".") else { return str }
        var result = str
        while result.hasSuffix("0") && !result.hasSuffix(".0") {
            result.removeLast()
        }
        if result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }

    private func parseNumber(_ str: String) -> Double? {
        let cleaned = str
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty {
            return 0.0
        }

        return Double(cleaned)
    }
}

/// A variant that binds to an optional Double
struct OptionalNumericTextField: View {
    let placeholder: String
    @Binding var value: Double?
    var fractionDigits: Int = 2
    var onCommit: (() -> Void)? = nil

    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $textValue)
            .focused($isFocused)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .onChange(of: isFocused) { _, focused in
                if focused {
                    if let val = value, val != 0 {
                        textValue = formatForEditing(val)
                    } else {
                        textValue = ""
                    }
                } else {
                    if textValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        value = nil
                    } else if let parsed = parseNumber(textValue) {
                        value = parsed
                    }
                    onCommit?()
                    textValue = value.map { formatForDisplay($0) } ?? ""
                }
            }
            .onAppear {
                textValue = value.map { formatForDisplay($0) } ?? ""
            }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    textValue = newValue.map { formatForDisplay($0) } ?? ""
                }
            }
    }

    private func formatForEditing(_ val: Double) -> String {
        let formatted = String(format: "%.\(fractionDigits)f", val)
        return trimTrailingZeros(formatted)
    }

    private func formatForDisplay(_ val: Double) -> String {
        return String(format: "%.\(fractionDigits)f", val)
    }

    private func trimTrailingZeros(_ str: String) -> String {
        guard str.contains(".") else { return str }
        var result = str
        while result.hasSuffix("0") && !result.hasSuffix(".0") {
            result.removeLast()
        }
        if result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }

    private func parseNumber(_ str: String) -> Double? {
        let cleaned = str
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty {
            return nil
        }

        return Double(cleaned)
    }
}

#if DEBUG
struct NumericTextField_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            NumericTextField(placeholder: "Value", value: .constant(1234.567), fractionDigits: 3)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
        }
        .padding()
    }
}
#endif
