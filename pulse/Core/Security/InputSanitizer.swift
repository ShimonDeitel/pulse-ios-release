import Foundation

// MARK: - Input Sanitizer

/// Server-side sanitization happens at the Lambda level.
/// Client-side sanitization is defense-in-depth — strip obvious
/// injection attempts before they leave the device.
enum InputSanitizer {

    // MARK: - Text Sanitization

    /// Strip HTML tags and limit length. Use for all user text input.
    static func sanitize(_ input: String, maxLength: Int = 5000) -> String {
        var result = input

        // Strip HTML/XML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Strip null bytes
        result = result.replacingOccurrences(of: "\0", with: "")

        // Normalize whitespace (no leading/trailing, collapse internal)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit length
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }

        return result
    }

    /// Sanitize for display name (stricter: alphanumeric + spaces + basic punctuation)
    static func sanitizeName(_ input: String, maxLength: Int = 100) -> String {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}\\s.'-]",
                with: "",
                options: .regularExpression
            )
        return String(cleaned.prefix(maxLength))
    }

    /// Sanitize email (lowercase, trim, basic validation)
    static func sanitizeEmail(_ input: String) -> String? {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let pattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        guard cleaned.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned
    }

    /// Sanitize goal title
    static func sanitizeTitle(_ input: String) -> String {
        sanitize(input, maxLength: 200)
    }

    /// Sanitize goal description
    static func sanitizeDescription(_ input: String) -> String {
        sanitize(input, maxLength: 2000)
    }

    /// Sanitize mentor chat message
    static func sanitizeMessage(_ input: String) -> String {
        sanitize(input, maxLength: 10000)
    }

    // MARK: - UUID Validation

    static func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }

    // MARK: - Numeric Validation

    static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }

    /// Validate progress percentage (0-100)
    static func sanitizeProgress(_ value: Double) -> Double {
        clamp(value, min: 0, max: 100)
    }

    /// Validate temperature for AI calls (0-2)
    static func sanitizeTemperature(_ value: Double) -> Double {
        clamp(value, min: 0, max: 2)
    }
}
