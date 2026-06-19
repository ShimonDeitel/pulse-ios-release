import Foundation

// MARK: - Proxy Session Errors

enum ProxySessionError: LocalizedError {
    /// No Apple identity available — the user must sign in.
    case notSignedIn
    /// The proxy rejected the Apple identity token (typically because it has
    /// expired). The user needs to sign in with Apple again to mint a fresh one.
    case appleTokenRejected
    /// Any other non-200 from /v1/session.
    case exchangeFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to use AI features."
        case .appleTokenRejected:
            return "Your sign-in expired. Please sign in with Apple again to continue using AI."
        case .exchangeFailed(let code, _):
            return "Couldn't start an AI session (\(code)). Please try again."
        }
    }
}

// MARK: - Proxy Session Manager
//
// Obtains and caches the Pulse *session* JWT used to authenticate /v1/chat.
//
// Flow: at sign-in the app captures a FRESH Apple identity token (short-lived).
// We POST it to /v1/session, which verifies it against Apple and mints a 60-day
// session JWT. We cache that JWT (Keychain) and send it as `Authorization:
// Bearer` on every chat call. Because the session JWT lasts 60 days, we rarely
// re-exchange. When it finally nears expiry — or a chat returns 401 — we try to
// re-exchange; that needs a fresh Apple token, so a long-dormant user may be
// asked to sign in again (surfaced as `.appleTokenRejected`).
//
// An `actor` serializes access to the cached token so concurrent AI calls don't
// each kick off their own exchange (no stampede, no races).
actor ProxySessionManager {
    static let shared = ProxySessionManager()
    private init() {}

    private let keychain = KeychainManager.shared
    private var cached: String?
    private var exchangeTask: Task<String, Error>?

    /// Return a usable session token, exchanging if the cached one is missing or
    /// within a day of expiry. Concurrent callers share the same in-flight exchange.
    func token() async throws -> String {
        if let t = cached, !isExpiringSoon(t) { return t }
        if let stored = keychain.retrieve(key: .proxySessionToken), !isExpiringSoon(stored) {
            cached = stored
            return stored
        }
        if let pending = exchangeTask { return try await pending.value }
        let task = Task { try await exchange() }
        exchangeTask = task
        defer { exchangeTask = nil }
        return try await task.value
    }

    /// Drop the cached/stored session so the next `token()` re-exchanges. Call
    /// this after a 401 from the chat endpoint, or on sign-out.
    func invalidate() {
        cached = nil
        keychain.delete(key: .proxySessionToken)
    }

    /// Proactively mint a session at sign-in, while the Apple token is freshest.
    /// Best-effort: failures are swallowed (the first AI call will retry).
    func refreshAtSignIn() async {
        cached = nil
        keychain.delete(key: .proxySessionToken)
        _ = try? await exchange()
    }

    // MARK: - Exchange

    private func exchange() async throws -> String {
        guard let url = ProxyConfig.sessionURL else { throw GeminiDirectError.invalidURL }

        // POST an Apple identity token; return (statusCode, sessionToken?).
        func post(_ idToken: String) async throws -> (Int, String?) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["identityToken": idToken])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GeminiDirectError.noResponse }
            if http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["sessionToken"] as? String, !token.isEmpty {
                return (200, token)
            }
            return (http.statusCode, nil)
        }

        // Start from the stored Apple identity token. If there is none but the
        // user is signed in, mint a fresh one up front (typically the very first
        // session on this install, or after the proxy was first enabled).
        var idToken = keychain.retrieve(key: .cognitoIdToken) ?? ""
        if idToken.isEmpty {
            guard AuthManager.shared.isAuthenticated else { throw ProxySessionError.notSignedIn }
            idToken = (await AuthManager.shared.refreshAppleIdentityToken()) ?? ""
            guard !idToken.isEmpty else { throw ProxySessionError.appleTokenRejected }
        }

        var (status, token) = try await post(idToken)

        // 401 = the proxy rejected the token (almost always because it expired —
        // Apple identity tokens are short-lived). Mint a fresh one via a quick
        // Sign in with Apple and retry ONCE. This is what keeps AI working when a
        // session lapsed or was never minted while the token was fresh, without
        // forcing the user to sign out and back in.
        if status == 401,
           AuthManager.shared.isAuthenticated,
           let fresh = await AuthManager.shared.refreshAppleIdentityToken(), !fresh.isEmpty {
            (status, token) = try await post(fresh)
        }

        if status == 200, let sessionToken = token {
            cached = sessionToken
            keychain.save(key: .proxySessionToken, value: sessionToken)
            return sessionToken
        }
        if status == 401 { throw ProxySessionError.appleTokenRejected }
        throw ProxySessionError.exchangeFailed(status, "")
    }

    // MARK: - Local expiry check (decode the JWT payload, read `exp`)

    /// True if the token is malformed or within 24h of expiring.
    private func isExpiringSoon(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Self.base64urlDecode(String(parts[1])),
              let obj = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = (obj["exp"] as? NSNumber)?.doubleValue else {
            return true
        }
        return Date().addingTimeInterval(24 * 60 * 60) >= Date(timeIntervalSince1970: exp)
    }

    private static func base64urlDecode(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while str.count % 4 != 0 { str += "=" }
        return Data(base64Encoded: str)
    }
}
