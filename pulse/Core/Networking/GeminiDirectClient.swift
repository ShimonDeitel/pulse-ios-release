import Foundation

/// AI client — direct Groq (OpenAI-compatible) inference.
/// Class name kept for backward compatibility with all existing call sites.
///
/// SECURITY: this client carries NO embedded provider key. A provider key must
/// NEVER ship in the app binary — it would be trivially extractable (`strings`
/// on the IPA) and could be drained against our account. Production AI goes
/// through the server-side proxy (`ProxyConfig` + `DeepSeekClient`), which holds
/// the real key. This direct client is a development/escape-hatch path that only
/// works when a key has been explicitly provisioned into the Keychain at runtime;
/// with no key it reports `.noAPIKey` and the app degrades honestly.
final class GeminiDirectClient: @unchecked Sendable {
    static let shared = GeminiDirectClient()

    private let session: URLSession
    private let keychain = KeychainManager.shared

    // MARK: - Configuration

    /// Groq's OpenAI-compatible endpoint
    private let chatEndpoint = "https://api.groq.com/openai/v1/chat/completions"

    /// Default model — Llama 3.3 70B is the most capable on Groq
    private let defaultModel = "llama-3.3-70b-versatile"

    /// Vision-capable model for photo analysis
    private let visionModel = "meta-llama/llama-4-scout-17b-16e-instruct"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Key management (public surface unchanged)

    /// True only when a key has been provisioned into the Keychain at runtime.
    /// No embedded key exists, so this is false on a fresh install — the app
    /// then relies on the server proxy for AI.
    var hasAPIKey: Bool { hasCustomAPIKey }

    var hasCustomAPIKey: Bool {
        guard let key = keychain.retrieve(key: .geminiAPIKey) else { return false }
        return !key.isEmpty
    }

    func setAPIKey(_ key: String) {
        keychain.save(key: .geminiAPIKey, value: key)
    }

    /// The provisioned key, or nil. There is intentionally NO built-in fallback
    /// key — callers that get nil must surface `.noAPIKey` rather than ship a
    /// secret in the binary.
    func getAPIKey() -> String? {
        guard let custom = keychain.retrieve(key: .geminiAPIKey), !custom.isEmpty else {
            return nil
        }
        return custom
    }

    func removeAPIKey() {
        keychain.delete(key: .geminiAPIKey)
    }

    // MARK: - Text Generation

    func generateContent(
        prompt: String,
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        temperature: Double = 0.7,
        maxTokens: Int = 8192,
        forceJSON: Bool = false
    ) async throws -> String {
        // Retry up to 3 times on transient network failures (dropped connection,
        // timeout, DNS hiccup). Common when view re-mounts mid-flight.
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await performGenerate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    conversationHistory: conversationHistory,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    forceJSON: forceJSON
                )
            } catch {
                lastError = error
                // Retry only on transient network errors
                if let urlError = error as? URLError,
                   [.networkConnectionLost, .timedOut, .notConnectedToInternet,
                    .cannotFindHost, .dnsLookupFailed, .cancelled].contains(urlError.code) {
                    // Exponential backoff: 300ms, 800ms
                    let delay = attempt == 0 ? 300_000_000 : 800_000_000
                    try? await Task.sleep(nanoseconds: UInt64(delay))
                    continue
                }
                // Non-network errors → fail immediately
                throw error
            }
        }
        // Retries exhausted on a network error → surface a clear offline message.
        if let urlError = lastError as? URLError,
           [.networkConnectionLost, .timedOut, .notConnectedToInternet,
            .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost].contains(urlError.code) {
            throw GeminiDirectError.offline
        }
        throw lastError ?? GeminiDirectError.noResponse
    }

    private func performGenerate(
        prompt: String,
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        temperature: Double,
        maxTokens: Int,
        forceJSON: Bool = false
    ) async throws -> String {
        guard let apiKey = getAPIKey() else {
            throw GeminiDirectError.noAPIKey
        }

        guard let url = URL(string: chatEndpoint) else {
            throw GeminiDirectError.invalidURL
        }

        // Build messages array (OpenAI format)
        var messages: [[String: Any]] = []

        // System prompt comes first
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }

        // Conversation history (last 20 turns)
        for msg in conversationHistory.suffix(20) {
            // Groq accepts "user" / "assistant" — pass through
            let role = (msg.role == "assistant" || msg.role == "model") ? "assistant" : "user"
            messages.append(["role": role, "content": msg.content])
        }

        // Current user message
        messages.append(["role": "user", "content": prompt])

        // Groq has a 32K-output cap on most models; clamp to safe upper bound
        let clampedMax = min(maxTokens, 8000)

        var body: [String: Any] = [
            "model": defaultModel,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": clampedMax,
            "top_p": 0.95,
            "stream": false
        ]
        // Force JSON mode when caller asked for it. Groq supports the OpenAI
        // response_format directive on Llama 3.x models — drastically reduces
        // malformed-JSON failures vs. relying on the prompt alone.
        if forceJSON {
            body["response_format"] = ["type": "json_object"]
        }

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
            if httpResponse.statusCode == 401 {
                throw GeminiDirectError.invalidAPIKey
            }
            if httpResponse.statusCode == 429 {
                throw GeminiDirectError.rateLimited
            }
            throw GeminiDirectError.serverError(httpResponse.statusCode, errorMsg)
        }

        // Parse OpenAI-format response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GeminiDirectError.parseError
        }

        return content
    }

    // MARK: - JSON Generation (strips markdown fences)

    func generateJSON(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.5,
        maxTokens: Int = 8192
    ) async throws -> String {
        // Append explicit JSON-only instruction in case the model ignores the
        // response_format directive on a given call.
        let jsonPrompt = prompt + "\n\nReturn ONLY valid JSON. No markdown fences, no prose."
        let response = try await generateContent(
            prompt: jsonPrompt,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens,
            forceJSON: true
        )
        return extractJSON(from: response)
    }

    // MARK: - Vision (photo analysis)

    func analyzeImages(
        prompt: String,
        images: [(data: Data, mimeType: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 8000
    ) async throws -> String {
        guard let apiKey = getAPIKey() else {
            throw GeminiDirectError.noAPIKey
        }

        guard let url = URL(string: chatEndpoint) else {
            throw GeminiDirectError.invalidURL
        }

        // Build content array with text + images (OpenAI multi-modal format)
        var contentParts: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]

        for image in images {
            let base64 = image.data.base64EncodedString()
            contentParts.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(image.mimeType);base64,\(base64)"
                ]
            ])
        }

        var messages: [[String: Any]] = []
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": contentParts])

        // Llama-4-Scout supports up to 8K output. Clamp to safe upper bound.
        let clampedMax = max(512, min(maxTokens, 8000))

        let body: [String: Any] = [
            "model": visionModel,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": clampedMax,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
                throw GeminiDirectError.offline
            default:
                throw urlError
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiDirectError.noResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 { throw GeminiDirectError.invalidAPIKey }
            if httpResponse.statusCode == 429 { throw GeminiDirectError.rateLimited }
            throw GeminiDirectError.serverError(httpResponse.statusCode, errorMsg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GeminiDirectError.parseError
        }

        return content
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` wrapping
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

// MARK: - Errors

enum GeminiDirectError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidURL
    case noResponse
    case rateLimited
    case offline
    case parseError
    case serverError(Int, String)
    /// The AI service is temporarily unavailable (proxy pot exhausted, or the
    /// upstream DeepSeek account is unfunded/down). Not the user's fault.
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI is temporarily unavailable. Please try again in a moment."
        case .invalidAPIKey:
            return "Invalid API key. Please check your key in Settings."
        case .invalidURL:
            return "Invalid API endpoint."
        case .noResponse:
            return "No response from AI service."
        case .rateLimited:
            return "Usage limit reached. Limit resets tomorrow."
        case .offline:
            return "There's no internet connection. Try again later."
        case .parseError:
            return "Failed to parse AI response."
        case .serverError(let code, _):
            return "AI service error (\(code)). Please try again in a moment."
        case .serviceUnavailable:
            return "AI is temporarily unavailable. Please try again in a little while."
        }
    }
}
