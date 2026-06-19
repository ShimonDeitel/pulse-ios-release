import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - DeepSeek V4 Model

/// The two DeepSeek V4 variants we use. `pro` is the flagship (1.6T MoE) used for
/// every task by default; `flash` is the cheaper model we downshift to when the
/// user's daily budget is nearly spent, so the experience degrades gracefully
/// instead of cutting off mid-day.
enum DeepSeekModel: String, Sendable {
    case pro
    case flash

    var apiName: String {
        switch self {
        case .pro:   return "deepseek-v4-pro"
        case .flash: return "deepseek-v4-flash"
        }
    }

    // Pricing per 1,000,000 tokens (USD). DeepSeek bills prompt tokens at two
    // rates depending on whether they hit the context cache.
    var inputCacheHitPerM: Double {
        switch self {
        case .pro:   return 0.003625   // 75% launch promo
        case .flash: return 0.0028
        }
    }
    var inputCacheMissPerM: Double {
        switch self {
        case .pro:   return 0.435      // 75% launch promo
        case .flash: return 0.14
        }
    }
    var outputPerM: Double {
        switch self {
        case .pro:   return 0.87       // 75% launch promo
        case .flash: return 0.28
        }
    }
}

// MARK: - Usage / cost

/// Token accounting returned in every DeepSeek response. We turn this into a USD
/// figure so the daily budget tracker can debit the user's allowance precisely.
struct DeepSeekUsage: Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let cacheHitTokens: Int
    let cacheMissTokens: Int

    static let zero = DeepSeekUsage(promptTokens: 0, completionTokens: 0, cacheHitTokens: 0, cacheMissTokens: 0)

    /// Real cost in USD for this call on the given model.
    func costUSD(for model: DeepSeekModel) -> Double {
        // Prefer the explicit cache breakdown; if absent, treat all prompt tokens
        // as cache-miss (the conservative/expensive assumption).
        let hit = max(0, cacheHitTokens)
        let miss = cacheMissTokens > 0 ? cacheMissTokens : max(0, promptTokens - cacheHitTokens)
        let inputCost = Double(hit) / 1_000_000.0 * model.inputCacheHitPerM
                      + Double(miss) / 1_000_000.0 * model.inputCacheMissPerM
        let outputCost = Double(completionTokens) / 1_000_000.0 * model.outputPerM
        return inputCost + outputCost
    }
}

// MARK: - Tool calling

/// A function the model asked us to run. `argumentsJSON` is the raw JSON object
/// string the model produced for the call (may be `"{}"`).
struct DeepSeekToolCall: Identifiable, Sendable {
    let id: String
    let name: String
    let argumentsJSON: String
}

/// Everything a single DeepSeek turn returns: assistant text (possibly empty when
/// the model is making tool calls), any tool calls, token usage, and which model
/// actually served the request (so callers can price it correctly).
struct DeepSeekResult: Sendable {
    let text: String
    let toolCalls: [DeepSeekToolCall]
    let usage: DeepSeekUsage
    let model: DeepSeekModel
    /// The raw assistant message dict, kept so a tool-calling loop can append it
    /// back into the conversation verbatim before adding tool results.
    let rawAssistantMessage: [String: Any]
}

// MARK: - DeepSeek V4 Client

/// OpenAI-compatible client for the DeepSeek V4 API. This is the single transport
/// for every AI task in Pulse — text, JSON, vision, and tool/function calling.
/// It is pure transport: budget gating and model selection live in `AIRouter`.
final class DeepSeekClient: @unchecked Sendable {
    static let shared = DeepSeekClient()

    private let session: URLSession
    private let keychain = KeychainManager.shared

    /// DeepSeek's OpenAI-compatible chat endpoint.
    private let chatEndpoint = "https://api.deepseek.com/chat/completions"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 200
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Key management

    /// True when AI is reachable. With the proxy enabled the shared key lives
    /// server-side, so no local key is needed — the app just needs a session.
    /// Otherwise it's true once a DeepSeek key is stored in the Keychain (dev).
    var isConfigured: Bool {
        if ProxyConfig.isEnabled { return true }
        guard let k = keychain.retrieve(key: .deepSeekAPIKey) else { return false }
        return !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setAPIKey(_ key: String) {
        keychain.save(key: .deepSeekAPIKey, value: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func getAPIKey() -> String? {
        guard let k = keychain.retrieve(key: .deepSeekAPIKey), !k.isEmpty else { return nil }
        return k
    }

    func removeAPIKey() {
        keychain.delete(key: .deepSeekAPIKey)
    }

    // MARK: - Core chat (returns full result with usage + tool calls)

    /// The single low-level entry point. Takes a fully-built OpenAI-format
    /// `messages` array, optional `tools`, and returns text + tool calls + usage.
    /// Retries transient network failures with exponential backoff.
    func chat(
        messages: [[String: Any]],
        model: DeepSeekModel,
        tools: [[String: Any]]? = nil,
        toolChoice: String = "auto",
        temperature: Double = 0.7,
        maxTokens: Int = 8192,
        forceJSON: Bool = false
    ) async throws -> DeepSeekResult {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                // In DEBUG, a Keychain DeepSeek key takes precedence so AI is
                // testable without the proxy + Apple-token round-trip (e.g. on the
                // simulator with no real Sign in with Apple). Release/TestFlight has
                // no such key and the direct path is compiled out, so it always
                // routes through the proxy.
                #if DEBUG
                let preferDirectKey = getAPIKey() != nil
                #else
                let preferDirectKey = false
                #endif
                if ProxyConfig.isEnabled && !preferDirectKey {
                    return try await performProxyChat(
                        messages: messages, model: model, tools: tools, toolChoice: toolChoice,
                        temperature: temperature, maxTokens: maxTokens, forceJSON: forceJSON
                    )
                }
                #if DEBUG
                return try await performChat(
                    messages: messages, model: model, tools: tools, toolChoice: toolChoice,
                    temperature: temperature, maxTokens: maxTokens, forceJSON: forceJSON
                )
                #else
                throw GeminiDirectError.serviceUnavailable
                #endif
            } catch {
                lastError = error
                if let urlError = error as? URLError,
                   [.networkConnectionLost, .timedOut, .notConnectedToInternet,
                    .cannotFindHost, .dnsLookupFailed, .cancelled].contains(urlError.code) {
                    let delay = attempt == 0 ? 400_000_000 : 1_000_000_000
                    try? await Task.sleep(nanoseconds: UInt64(delay))
                    continue
                }
                throw error
            }
        }
        if let urlError = lastError as? URLError,
           [.networkConnectionLost, .timedOut, .notConnectedToInternet,
            .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost].contains(urlError.code) {
            throw GeminiDirectError.offline
        }
        throw lastError ?? GeminiDirectError.noResponse
    }

    // MARK: Direct path (dev): talk to DeepSeek with a local key.

    private func performChat(
        messages: [[String: Any]],
        model: DeepSeekModel,
        tools: [[String: Any]]?,
        toolChoice: String,
        temperature: Double,
        maxTokens: Int,
        forceJSON: Bool
    ) async throws -> DeepSeekResult {
        guard let apiKey = getAPIKey() else { throw GeminiDirectError.noAPIKey }
        guard let url = URL(string: chatEndpoint) else { throw GeminiDirectError.invalidURL }

        let body = buildChatBody(
            messages: messages, model: model, tools: tools, toolChoice: toolChoice,
            temperature: temperature, maxTokens: maxTokens, forceJSON: forceJSON
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiDirectError.noResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 { throw GeminiDirectError.invalidAPIKey }
            if httpResponse.statusCode == 402 { throw GeminiDirectError.serverError(402, "DeepSeek account has insufficient balance.") }
            if httpResponse.statusCode == 429 { throw GeminiDirectError.rateLimited }
            throw GeminiDirectError.serverError(httpResponse.statusCode, errorMsg)
        }
        return try parseChatResult(data: data, model: model)
    }

    // MARK: Proxy path (prod): talk to the Pulse AI proxy with a session JWT.
    // The proxy holds the DeepSeek key, meters the user, and forwards the call.
    // It returns DeepSeek's response verbatim on success, so parsing is identical.

    private func performProxyChat(
        messages: [[String: Any]],
        model: DeepSeekModel,
        tools: [[String: Any]]?,
        toolChoice: String,
        temperature: Double,
        maxTokens: Int,
        forceJSON: Bool
    ) async throws -> DeepSeekResult {
        guard let url = ProxyConfig.chatURL else { throw GeminiDirectError.invalidURL }
        let body = buildChatBody(
            messages: messages, model: model, tools: tools, toolChoice: toolChoice,
            temperature: temperature, maxTokens: maxTokens, forceJSON: forceJSON
        )
        let payload = try JSONSerialization.data(withJSONObject: body)

        // Try with the cached session token; on a 401 re-exchange once and retry.
        for attempt in 0..<2 {
            let token = try await ProxySessionManager.shared.token()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // Tier routing hint as a HEADER (not a body field) so the proxy can
            // split free vs paid traffic WITHOUT the value ever reaching the
            // upstream model — old proxy builds simply ignore the header.
            request.setValue(SubscriptionManager.shared.isPro ? "pro" : "free",
                             forHTTPHeaderField: "X-Pulse-Tier")
            request.httpBody = payload

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiDirectError.noResponse
            }
            if httpResponse.statusCode == 401 && attempt == 0 {
                await ProxySessionManager.shared.invalidate()
                continue
            }
            guard httpResponse.statusCode == 200 else {
                throw mapProxyError(status: httpResponse.statusCode, data: data)
            }
            return try parseChatResult(data: data, model: model)
        }
        throw GeminiDirectError.noResponse
    }

    /// Map a non-200 from the proxy onto the app's existing error vocabulary so
    /// the UI reacts correctly (limit modal, "try again later", re-auth, etc.).
    private func mapProxyError(status: Int, data: Data) -> Error {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
        switch status {
        case 401:
            // Session rejected even after a re-exchange → the Apple token is stale.
            return ProxySessionError.appleTokenRejected
        case 402:
            // Global pot exhausted, or DeepSeek's own insufficient-balance passthrough.
            return GeminiDirectError.serviceUnavailable
        case 429 where code == "user_cap":
            // Per-user monthly cap → the existing "you've used your monthly limit"
            // modal (no upgrade CTA, since Pro is the only paid plan).
            return AIRouterError.limitReached(tier: .pro, suggestedUpgrade: nil)
        case 429 where code == "daily_cap":
            // Today's paced slice of the monthly cap is spent but the month isn't —
            // a soft wall that lifts tomorrow. .rateLimited's copy already reads
            // "Usage limit reached. Limit resets tomorrow." which fits exactly.
            return GeminiDirectError.rateLimited
        case 429 where code == "free_busy":
            // Every FREE provider is rate-limited/down right now → the friendly
            // "too many users" copy with an upgrade nudge to Pro's Primary Access.
            return AIRouterError.limitReached(tier: .free, suggestedUpgrade: .pro)
        case 429:
            return GeminiDirectError.rateLimited
        default:
            return GeminiDirectError.serverError(status, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
    }

    // MARK: Shared body + response handling

    private func buildChatBody(
        messages: [[String: Any]],
        model: DeepSeekModel,
        tools: [[String: Any]]?,
        toolChoice: String,
        temperature: Double,
        maxTokens: Int,
        forceJSON: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.apiName,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max(256, min(maxTokens, 65_536)),
            "stream": false
        ]
        if forceJSON {
            body["response_format"] = ["type": "json_object"]
        }
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = toolChoice
        }
        return body
    }

    private func parseChatResult(data: Data, model: DeepSeekModel) throws -> DeepSeekResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw GeminiDirectError.parseError
        }

        let text = (message["content"] as? String) ?? ""

        // Parse tool calls if present.
        var toolCalls: [DeepSeekToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for call in rawCalls {
                guard let id = call["id"] as? String,
                      let fn = call["function"] as? [String: Any],
                      let name = fn["name"] as? String else { continue }
                let args = (fn["arguments"] as? String) ?? "{}"
                toolCalls.append(DeepSeekToolCall(id: id, name: name, argumentsJSON: args))
            }
        }

        // Parse usage (DeepSeek returns cache-hit / cache-miss breakdown).
        let usageDict = json["usage"] as? [String: Any]
        let usage = DeepSeekUsage(
            promptTokens: usageDict?["prompt_tokens"] as? Int ?? 0,
            completionTokens: usageDict?["completion_tokens"] as? Int ?? 0,
            cacheHitTokens: usageDict?["prompt_cache_hit_tokens"] as? Int ?? 0,
            cacheMissTokens: usageDict?["prompt_cache_miss_tokens"] as? Int ?? 0
        )

        return DeepSeekResult(
            text: text,
            toolCalls: toolCalls,
            usage: usage,
            model: model,
            rawAssistantMessage: message
        )
    }

    // MARK: - Convenience: text generation

    func generateContent(
        prompt: String,
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        model: DeepSeekModel = .flash,
        temperature: Double = 0.7,
        maxTokens: Int = 8192,
        forceJSON: Bool = false
    ) async throws -> DeepSeekResult {
        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        for msg in conversationHistory.suffix(20) {
            let role = (msg.role == "assistant" || msg.role == "model") ? "assistant" : "user"
            messages.append(["role": role, "content": msg.content])
        }
        messages.append(["role": "user", "content": prompt])

        return try await chat(
            messages: messages, model: model,
            temperature: temperature, maxTokens: maxTokens, forceJSON: forceJSON
        )
    }

    // MARK: - Convenience: JSON generation (strips markdown fences)

    func generateJSON(
        prompt: String,
        systemPrompt: String? = nil,
        model: DeepSeekModel = .flash,
        temperature: Double = 0.5,
        maxTokens: Int = 8192
    ) async throws -> DeepSeekResult {
        let jsonPrompt = prompt + "\n\nReturn ONLY valid JSON. No markdown fences, no prose."
        let result = try await generateContent(
            prompt: jsonPrompt, systemPrompt: systemPrompt, model: model,
            temperature: temperature, maxTokens: maxTokens, forceJSON: true
        )
        return DeepSeekResult(
            text: extractJSON(from: result.text),
            toolCalls: result.toolCalls,
            usage: result.usage,
            model: result.model,
            rawAssistantMessage: result.rawAssistantMessage
        )
    }

    // MARK: - Convenience: vision (photo analysis)

    func analyzeImages(
        prompt: String,
        images: [(data: Data, mimeType: String)],
        systemPrompt: String? = nil,
        model: DeepSeekModel = .flash,
        temperature: Double = 0.7,
        maxTokens: Int = 8192
    ) async throws -> DeepSeekResult {
        var contentParts: [[String: Any]] = [["type": "text", "text": prompt]]
        for image in images {
            // Downscale + re-encode before base64. A full-res iPhone photo is
            // several MB and blew past the proxy's prompt-size cap (413 "payload
            // too large" on Transformation + meal photos). Shrinking also cuts
            // vision cost and latency. Falls back to the original on decode fail.
            if let small = Self.downscaledJPEG(image.data, maxDimension: 768, quality: 0.45) {
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(small.base64EncodedString())"]
                ])
            } else {
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"]
                ])
            }
        }
        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": contentParts])

        return try await chat(
            messages: messages, model: model,
            temperature: temperature, maxTokens: maxTokens
        )
    }

    // MARK: - Helpers

    /// Downscale + JPEG-re-encode image data so vision requests stay small
    /// (well under the proxy's MAX_PROMPT_BYTES) and cheap. Returns nil if the
    /// data can't be decoded as an image, so the caller keeps the original.
    static func downscaledJPEG(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let longest = max(w, h)
        let scale = longest > maxDimension ? maxDimension / longest : 1.0
        let target = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
        #else
        return nil
        #endif
    }

    private func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
