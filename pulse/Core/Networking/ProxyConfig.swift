import Foundation

// MARK: - Proxy Configuration
//
// Server-side AI proxy switch. When `baseURL` is non-empty, EVERY DeepSeek call
// is routed through the Pulse AI proxy (the Cloudflare Worker in `ai-proxy/`),
// which holds the shared DeepSeek key, meters each user to a monthly cap, and
// hard-stops at a global pot ceiling. The app then carries only a short Pulse
// session token — never the DeepSeek key.
//
// When `baseURL` is empty, the app uses the legacy path: a DeepSeek key stored
// in the Keychain (dev), or the transitional Groq bridge if no key is present.
// This keeps local/dev builds working until the proxy is deployed.
//
// To go live: deploy the Worker (`cd ai-proxy && npm run deploy`), then set the
// URL via the `PulseProxyBaseURL` build setting (no source edit, no key in the
// binary) — see below. e.g. "https://pulse-ai-proxy.<your-subdomain>.workers.dev".
enum ProxyConfig {
    /// Deployed Worker base URL. Empty disables the proxy (legacy/dev path).
    ///
    /// Resolution order (first non-empty wins):
    ///   1. The `PulseProxyBaseURL` Info.plist key — injected at build time from
    ///      the `INFOPLIST_KEY_PulseProxyBaseURL` / `PULSE_PROXY_BASE_URL` build
    ///      setting (or an .xcconfig). This is the production path: the deploy
    ///      URL lives in build config, NOT in committed source, so flipping the
    ///      proxy on for a release archive is a setting change, not a code edit.
    ///   2. `overrideBaseURL` — a compile-time fallback, normally empty. Only set
    ///      this for a quick local experiment; never commit a non-empty value.
    ///
    /// NOTE: this is a public Worker URL, never a secret. No provider key is ever
    /// stored here or anywhere in the app (see GeminiDirectClient).
    static let overrideBaseURL = ""

    static var baseURL: String {
        if !overrideBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return overrideBaseURL
        }
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "PulseProxyBaseURL") as? String,
           !fromPlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           // Guard against the unsubstituted build-setting placeholder shipping as a literal.
           !fromPlist.contains("$(") {
            return fromPlist
        }
        return ""
    }

    /// True once a proxy URL has been configured.
    static var isEnabled: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static var trimmedBase: String {
        var b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.hasSuffix("/") { b.removeLast() }
        return b
    }

    /// POST: exchange a fresh Apple identity token for a 60-day Pulse session JWT.
    static var sessionURL: URL? { URL(string: trimmedBase + "/v1/session") }

    /// POST: the metered DeepSeek chat endpoint (Bearer = session JWT).
    static var chatURL: URL? { URL(string: trimmedBase + "/v1/chat") }

    /// GET: the user's remaining budget + pot status (Bearer = session JWT).
    static var budgetURL: URL? { URL(string: trimmedBase + "/v1/budget") }
}
