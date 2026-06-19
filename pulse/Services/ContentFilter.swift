import Foundation

// MARK: - Content filter

/// Lightweight on-device profanity / explicit-content filter. Powers the app's
/// always-on 13+ experience — e.g. masking anything objectionable in AI mentor
/// output before it is shown. Not a substitute for server-side moderation, but
/// it satisfies the "filter objectionable material" requirement and gives users
/// a clean default experience.
enum ContentFilter {

    /// Word stems that flag a string as objectionable. Matched as whole words /
    /// substrings, case-insensitively, after stripping leetspeak digits.
    private static let blocklist: [String] = [
        // sexual / explicit
        "fuck", "fuk", "fck", "shit", "sht", "cunt", "cock", "dick", "pussy",
        "porn", "pornhub", "xxx", "nude", "nudes", "naked", "boobs", "tits",
        "blowjob", "handjob", "cum", "jizz", "anal", "deepthroat", "creampie",
        "milf", "hentai", "rape", "molest", "pedo", "pedophile", "incest",
        "bestiality", "fetish", "bdsm", "horny", "slut", "whore", "hooker",
        "escort", "onlyfans", "camgirl", "sext", "nsfw",
        // hate / slurs (stems)
        "nigger", "nigga", "faggot", "fag", "retard", "kike", "spic", "chink",
        "wetback", "tranny",
        // violence / self-harm
        "kill yourself", "kys", "suicide method", "how to kill",
        // scam / spam
        "free crypto", "double your money", "telegram @", "click this link",
        "wire transfer", "gift card", "seed phrase",
    ]

    /// Substrings that are too short / common to safely substring-match, so we
    /// require word boundaries for them (handled by the tokenizer below).
    private static let exactWordOnly: Set<String> = ["fag", "cum", "anal", "kys", "xxx"]

    static func containsObjectionable(_ raw: String) -> Bool {
        guard !raw.isEmpty else { return false }
        let normalized = normalize(raw)
        let tokens = Set(normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        for term in blocklist {
            if term.contains(" ") {
                if normalized.contains(term) { return true }       // multi-word phrase
            } else if exactWordOnly.contains(term) {
                if tokens.contains(term) { return true }            // whole-word only
            } else if normalized.contains(term) {
                return true                                         // stem substring
            }
        }
        return false
    }

    /// Replace flagged words with a masked form for display.
    static func masked(_ raw: String) -> String {
        guard containsObjectionable(raw) else { return raw }
        var result = raw
        let normalizedSource = normalize(raw)
        for term in blocklist where !term.contains(" ") {
            guard normalizedSource.contains(term) else { continue }
            // Case-insensitive replace, preserving nothing — full mask.
            let mask = String(repeating: "*", count: max(term.count, 3))
            result = result.replacingOccurrences(
                of: term, with: mask, options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        return result
    }

    /// Lowercase, fold leetspeak digits to letters so "f4ggot"/"sh1t" still match.
    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        out.reserveCapacity(lowered.count)
        for ch in lowered {
            switch ch {
            case "0": out.append("o")
            case "1": out.append("i")
            case "3": out.append("e")
            case "4": out.append("a")
            case "5": out.append("s")
            case "7": out.append("t")
            case "@": out.append("a")
            case "$": out.append("s")
            default:  out.append(ch)
            }
        }
        return out
    }
}
