import Foundation

/// Share a saved quote as a "quote note" the recipient can open in Pulse and
/// save to *their* own Saved Quotes. We encode the quote into a `pulse://quote`
/// deep link (base64url, no padding) so it survives Messages/Mail/clipboard,
/// and decode it back on `onOpenURL`.
enum QuoteShare {
    static let scheme = "pulse"
    static let host = "quote"

    /// The deep link that re-opens this quote inside Pulse.
    static func importURL(_ quote: String) -> URL? {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return nil }
        let token = base64urlEncode(data)
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.queryItems = [URLQueryItem(name: "q", value: token)]
        return comps.url
    }

    /// Human-friendly share payload: the quote, attribution, and the deep link
    /// so the recipient can tap to save it in their own Pulse.
    static func shareText(_ quote: String) -> String {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["\u{201C}\(trimmed)\u{201D}", "", "— shared from Pulse"]
        if let url = importURL(trimmed) {
            lines.append("")
            lines.append("Open in Pulse to save it: \(url.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }

    /// Parse a `pulse://quote?q=…` deep link back into the original quote.
    static func decode(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "q" })?.value,
              let data = base64urlDecode(token),
              let quote = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - base64url (URL-safe, unpadded)

    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ token: String) -> Data? {
        var s = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-pad to a multiple of 4.
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }
}
