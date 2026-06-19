import Foundation

/// Live web search for grounding AI answers in real, current information. Used by
/// the mentor agent's `web_search` tool so "ask AI" chats can pull facts off the
/// internet instead of hallucinating. Backed by Tavily (key stored in Keychain).
///
/// Each search debits a small flat cost from the user's daily AI budget, since
/// search credits are a real per-call expense on top of DeepSeek tokens.
final class WebSearchService: @unchecked Sendable {
    static let shared = WebSearchService()

    private let session: URLSession
    private let keychain = KeychainManager.shared
    private let endpoint = "https://api.tavily.com/search"

    /// Flat per-search cost charged to the daily budget (Tavily advanced ≈ 2
    /// credits ≈ $0.008). Keeps the economics honest without per-credit metering.
    private let perSearchCostUSD = 0.008

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        self.session = URLSession(configuration: config)
    }

    // MARK: - Key management

    var isConfigured: Bool {
        guard let k = keychain.retrieve(key: .searchAPIKey) else { return false }
        return !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setAPIKey(_ key: String) {
        keychain.save(key: .searchAPIKey, value: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func getAPIKey() -> String? {
        guard let k = keychain.retrieve(key: .searchAPIKey), !k.isEmpty else { return nil }
        return k
    }

    func removeAPIKey() { keychain.delete(key: .searchAPIKey) }

    // MARK: - Search

    /// Run a live web search and return a compact, model-ready findings block:
    /// an optional direct answer followed by the top results (title, URL, snippet).
    /// Throws `GeminiDirectError.noAPIKey` when no search key is configured.
    func search(query: String, maxResults: Int = 5) async throws -> String {
        guard let apiKey = getAPIKey() else { throw GeminiDirectError.noAPIKey }
        guard let url = URL(string: endpoint) else { throw GeminiDirectError.invalidURL }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No query provided." }

        let body: [String: Any] = [
            "api_key": apiKey,                     // body form for broad compatibility
            "query": String(trimmed.prefix(400)),
            "search_depth": "advanced",
            "include_answer": true,
            "max_results": max(1, min(maxResults, 8))
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GeminiDirectError.noResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw GeminiDirectError.invalidAPIKey }
            if http.statusCode == 429 { throw GeminiDirectError.rateLimited }
            let msg = String(data: data, encoding: .utf8) ?? "Search error"
            throw GeminiDirectError.serverError(http.statusCode, msg)
        }

        // Charge the search to today's budget.
        DailyAIBudget.shared.record(costUSD: perSearchCostUSD)
        AISpendTracker.shared.recordUSD(perSearchCostUSD)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiDirectError.parseError
        }

        var out = ""
        if let answer = json["answer"] as? String, !answer.isEmpty {
            out += "Answer: \(answer)\n\n"
        }
        if let results = json["results"] as? [[String: Any]], !results.isEmpty {
            out += "Sources:\n"
            for (i, r) in results.prefix(maxResults).enumerated() {
                let title = (r["title"] as? String) ?? "Untitled"
                let urlStr = (r["url"] as? String) ?? ""
                let content = (r["content"] as? String) ?? ""
                out += "\(i + 1). \(title)\n\(urlStr)\n\(String(content.prefix(500)))\n\n"
            }
        }
        return out.isEmpty ? "No results found." : out
    }
}
