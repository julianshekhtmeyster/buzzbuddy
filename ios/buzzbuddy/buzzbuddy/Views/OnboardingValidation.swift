import Foundation

/// Pure validation rules for onboarding/baseline-upgrade form fields, kept
/// separate from the views so they're directly testable. Ranges are
/// reasonable prototype bounds, not medical limits.
enum OnboardingValidation {
    static let weightRangeLbs: ClosedRange<Double> = 70...700
    static let heightRangeIn: ClosedRange<Double> = 36...96

    static func isValidWeightLbs(_ text: String) -> Bool {
        guard let value = Double(text) else { return false }
        return weightRangeLbs.contains(value)
    }

    /// Converts a feet + inches entry (e.g. "5" ft, "10" in) into total
    /// inches. `inches` may be blank (treated as 0) but if present must be
    /// 0..<12 -- a raw value like "510" in the inches field is rejected
    /// rather than silently accepted as 510 inches.
    static func totalHeightInches(feet: String, inches: String) -> Double? {
        guard let feetValue = Double(feet), feetValue >= 0 else { return nil }
        let inchesText = inches.trimmingCharacters(in: .whitespacesAndNewlines)
        let inchesValue: Double
        if inchesText.isEmpty {
            inchesValue = 0
        } else if let parsed = Double(inchesText), (0..<12).contains(parsed) {
            inchesValue = parsed
        } else {
            return nil
        }
        return feetValue * 12 + inchesValue
    }

    static func isValidHeight(feet: String, inches: String) -> Bool {
        guard let total = totalHeightInches(feet: feet, inches: inches) else { return false }
        return heightRangeIn.contains(total)
    }

    static func isNonEmpty(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
