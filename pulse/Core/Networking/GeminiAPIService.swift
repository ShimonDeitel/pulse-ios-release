import Foundation

/// GeminiAPIService — unified AI interface (legacy name kept so call sites don't
/// churn). Every method now delegates to `AIRouter`, which routes to DeepSeek V4
/// (Pro, auto-falling-back to Flash), enforces the per-day budget, and records
/// spend. ViewModels keep calling this facade; they don't care about the engine.
final class GeminiAPIService: @unchecked Sendable {
    static let shared = GeminiAPIService()

    private init() {}

    /// Whether an AI backend is wired (DeepSeek key, or the transitional Groq
    /// bridge). Tier/budget gating happens inside AIRouter per call.
    var isAvailable: Bool {
        DeepSeekClient.shared.isConfigured || GeminiDirectClient.shared.hasAPIKey
    }

    var statusMessage: String {
        isAvailable ? "Connected" : "AI not configured"
    }

    // MARK: - Text Generation (Mentor Chat, etc.)

    func sendMessage(
        userMessage: String,
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> String {
        try await AIRouter.shared.sendMessage(
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: - Vision (photo analysis)

    func sendVisionMessage(
        textPrompt: String,
        images: [(data: Data, mimeType: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 8192
    ) async throws -> String {
        try await AIRouter.shared.sendVisionMessage(
            textPrompt: textPrompt,
            images: images,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: - JSON Generation (analysis / roadmap)

    func sendMessageJSON(
        userMessage: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> String {
        try await AIRouter.shared.sendMessageJSON(
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }
}
