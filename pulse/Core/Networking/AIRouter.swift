import Foundation

// MARK: - AISpendTracker
// Tracks estimated USD AI spend per user per month for reporting. Persisted in
// UserDefaults so it survives restarts. Resets automatically when the calendar
// month rolls. The hard gate that actually pauses AI is DailyAIBudget; this is
// the rolling monthly view used by Settings/upgrade UI.

@Observable
final class AISpendTracker: @unchecked Sendable {
    static let shared = AISpendTracker()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private var monthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: Date())
    }

    private var spendKey: String { "ai_spend_usd_\(monthKey)" }

    /// Current month's spend in USD.
    var currentMonthSpendUSD: Double {
        defaults.double(forKey: spendKey)
    }

    /// Add the cost of one call by token counts + per-million prices.
    func record(inputTokens: Int, outputTokens: Int, costPerMillionInput: Double, costPerMillionOutput: Double) {
        let cost = (Double(inputTokens) / 1_000_000.0 * costPerMillionInput)
                 + (Double(outputTokens) / 1_000_000.0 * costPerMillionOutput)
        recordUSD(cost)
    }

    /// Add a precomputed USD cost.
    func recordUSD(_ cost: Double) {
        guard cost > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let key = spendKey
        defaults.set(defaults.double(forKey: key) + cost, forKey: key)
    }

    func hasExceededBudget(for tier: SubscriptionTier) -> Bool {
        currentMonthSpendUSD >= tier.monthlyAIBudgetUSD
    }

    func remainingBudget(for tier: SubscriptionTier) -> Double {
        max(0, tier.monthlyAIBudgetUSD - currentMonthSpendUSD)
    }

    func percentUsed(for tier: SubscriptionTier) -> Int {
        guard tier.monthlyAIBudgetUSD > 0, tier.monthlyAIBudgetUSD < Double.greatestFiniteMagnitude else { return 0 }
        return Int(min(100, (currentMonthSpendUSD / tier.monthlyAIBudgetUSD) * 100))
    }

    func resetCurrentMonth() {
        defaults.removeObject(forKey: spendKey)
    }
}

// MARK: - AIRouterError

enum AIRouterError: LocalizedError {
    /// Paid user hit a budget wall, or a free user tried to use AI at all.
    case limitReached(tier: SubscriptionTier, suggestedUpgrade: SubscriptionTier?)

    var errorDescription: String? {
        switch self {
        case .limitReached(let tier, _):
            if tier == .free {
                return "A lot of people are using Pulse right now. Try again in a moment — or upgrade to Pro for Primary Access: priority AI, no waiting."
            }
            return "You've used today's AI allowance on the \(tier.displayName) plan. It resets tomorrow."
        }
    }
}

// MARK: - AIRouter
//
// The single orchestration point for every AI call in Pulse. Responsibilities:
//   1. Tier gate — AI is free for EVERY tier (free routes to free providers, Pro
//      gets Primary Access). No tier block; the only hard stop is the budget/user-
//      cap gate below.
//   2. Model selection — DeepSeek V4 Pro normally; downshift to Flash when the
//      user's daily allowance is nearly spent so they keep working cheaply.
//   3. Spend recording — debits real DeepSeek cost from DailyAIBudget (the hard
//      gate) and the monthly AISpendTracker (reporting).
//
// Transitional provider bridge: until the DeepSeek key is supplied, text/JSON/
// vision calls fall back to the existing Groq client so the app keeps working
// and is testable. The bridge debits an *estimated* DeepSeek-priced cost so the
// daily-limit UX can be exercised pre-key. The moment a DeepSeek key is stored,
// Groq is never touched again.

final class AIRouter: @unchecked Sendable {
    static let shared = AIRouter()
    private init() {}

    private let deepSeek = DeepSeekClient.shared

    // MARK: - Gate + model selection

    /// Throws if the current tier can't make an AI call right now.
    private func gate() throws {
        // AI is available to EVERY tier now: free users route to free background
        // models, Pro users get Primary Access to the paid models. There is no
        // tier gate here anymore — the only hard stop is the budget below
        // (surfaced as 429 user_cap / "too many users" when exhausted).
        //
        // With the proxy enabled the server is the source of truth for the monthly
        // cap — it returns 429 {code:"user_cap"} when the user is tapped out, which
        // maps to the limit modal. Skip the bypassable device-side daily gate.
        if ProxyConfig.isEnabled { return }
        if DailyAIBudget.shared.hasExceededToday() {
            // Surfaces as "Usage limit reached. Limit resets tomorrow."
            throw GeminiDirectError.rateLimited
        }
    }

    /// Always DeepSeek Flash. The owner opted to run everything on Flash — it's
    /// much cheaper (Pro was burning the allowance far faster) and faster, which
    /// also helps plan generation finish well within the timeout. If we ever want
    /// a smarter task-based split (e.g. Pro for hard reasoning), branch here.
    private func currentModel() -> DeepSeekModel {
        return .flash
    }

    /// Debit a completed DeepSeek call from both the daily gate and the monthly
    /// reporting tracker.
    private func record(usage: DeepSeekUsage, model: DeepSeekModel) {
        let cost = usage.costUSD(for: model)
        DailyAIBudget.shared.record(costUSD: cost)
        AISpendTracker.shared.recordUSD(cost)
    }

    // MARK: - Text generation

    func sendMessage(
        userMessage: String,
        systemPrompt: String? = nil,
        conversationHistory: [(role: String, content: String)] = [],
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) async throws -> String {
        try gate()
        let model = currentModel()
        let prompt = InputSanitizer.sanitizeMessage(userMessage)
        let system = systemPrompt.map { InputSanitizer.sanitize($0) }
        let history = conversationHistory.map { (role: $0.role, content: InputSanitizer.sanitize($0.content)) }
        let temp = InputSanitizer.sanitizeTemperature(temperature)

        // Prefer Apple's FREE, private ON-DEVICE model for light conversational
        // turns when it's actually available (iOS 26+, eligible device). It costs
        // us nothing, so no spend is recorded. ANY failure (unavailable, empty,
        // error) falls through to the cloud path below. Heavy JSON/plan generation
        // and vision deliberately do NOT use this — they stay on cloud Gemini.
        if AppleOnDeviceLLM.isAvailable,
           let onDevice = try? await AppleOnDeviceLLM.generate(
               systemPrompt: system, userMessage: prompt, history: history),
           !onDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return onDevice
        }

        if deepSeek.isConfigured {
            let result = try await deepSeek.generateContent(
                prompt: prompt, systemPrompt: system, conversationHistory: history,
                model: model, temperature: temp, maxTokens: maxTokens
            )
            record(usage: result.usage, model: result.model)
            return result.text
        }

        // Transitional bridge → Groq. DEBUG-only, and compiled out of Release/
        // TestFlight entirely — production always routes through the proxy.
        #if DEBUG
        let text = try await GeminiDirectClient.shared.generateContent(
            prompt: prompt, systemPrompt: system, conversationHistory: history,
            temperature: temp, maxTokens: maxTokens
        )
        recordEstimated(input: prompt, system: system, history: history, output: text, model: model)
        return text
        #else
        throw GeminiDirectError.serviceUnavailable
        #endif
    }

    // MARK: - JSON generation

    func sendMessageJSON(
        userMessage: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.5,
        maxTokens: Int = 8192
    ) async throws -> String {
        try gate()
        let model = currentModel()
        let prompt = InputSanitizer.sanitizeMessage(userMessage)
        let system = systemPrompt.map { InputSanitizer.sanitize($0) }
        let temp = InputSanitizer.sanitizeTemperature(temperature)

        if deepSeek.isConfigured {
            let result = try await deepSeek.generateJSON(
                prompt: prompt, systemPrompt: system, model: model,
                temperature: temp, maxTokens: maxTokens
            )
            record(usage: result.usage, model: result.model)
            return result.text
        }

        // Transitional bridge → Groq. DEBUG-only, and compiled out of Release/
        // TestFlight entirely — production always routes through the proxy.
        #if DEBUG
        let text = try await GeminiDirectClient.shared.generateJSON(
            prompt: prompt, systemPrompt: system, temperature: temp, maxTokens: maxTokens
        )
        recordEstimated(input: prompt, system: system, history: [], output: text, model: model)
        return text
        #else
        throw GeminiDirectError.serviceUnavailable
        #endif
    }

    // MARK: - Vision

    func sendVisionMessage(
        textPrompt: String,
        images: [(data: Data, mimeType: String)],
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 8192
    ) async throws -> String {
        try gate()
        let model = currentModel()
        let prompt = InputSanitizer.sanitizeMessage(textPrompt)
        let system = systemPrompt.map { InputSanitizer.sanitize($0) }
        let temp = InputSanitizer.sanitizeTemperature(temperature)

        if deepSeek.isConfigured {
            let result = try await deepSeek.analyzeImages(
                prompt: prompt, images: images, systemPrompt: system,
                model: model, temperature: temp, maxTokens: maxTokens
            )
            record(usage: result.usage, model: result.model)
            return result.text
        }

        // Transitional bridge → Groq vision. DEBUG-only, and compiled out of
        // Release/TestFlight entirely — production always routes through the proxy.
        #if DEBUG
        let text = try await GeminiDirectClient.shared.analyzeImages(
            prompt: prompt, images: images, systemPrompt: system,
            temperature: temp, maxTokens: maxTokens
        )
        // Images dominate vision cost; add a flat token estimate per image.
        let imgTokens = images.count * 1_200
        recordEstimated(input: prompt, system: system, history: [], output: text,
                        model: model, extraInputTokens: imgTokens)
        return text
        #else
        throw GeminiDirectError.serviceUnavailable
        #endif
    }

    // MARK: - Tool / function calling (mentor agent, web search)

    /// Low-level tool-calling pass-through used by the agent loop. Requires a
    /// DeepSeek key — tool calling is not available on the transitional bridge.
    func chatWithTools(
        messages: [[String: Any]],
        tools: [[String: Any]],
        toolChoice: String = "auto",
        temperature: Double = 0.4,
        maxTokens: Int = 8192
    ) async throws -> DeepSeekResult {
        try gate()
        guard deepSeek.isConfigured else { throw GeminiDirectError.noAPIKey }
        let model = currentModel()
        let result = try await deepSeek.chat(
            messages: messages, model: model, tools: tools, toolChoice: toolChoice,
            temperature: temperature, maxTokens: maxTokens
        )
        record(usage: result.usage, model: result.model)
        return result
    }

    /// Whether full tool-calling (the app-controlling mentor agent) is live.
    var toolCallingAvailable: Bool { deepSeek.isConfigured }

    // MARK: - Estimated recording for the Groq bridge

    /// Rough char/4 token estimate priced at the selected DeepSeek model so the
    /// daily-budget UX behaves realistically before the real key is wired.
    private func recordEstimated(
        input: String, system: String?, history: [(role: String, content: String)],
        output: String, model: DeepSeekModel, extraInputTokens: Int = 0
    ) {
        func tok(_ s: String) -> Int { max(1, s.count / 4) }
        var inTokens = tok(input) + extraInputTokens
        if let system { inTokens += tok(system) }
        inTokens += history.reduce(0) { $0 + tok($1.content) }
        let usage = DeepSeekUsage(
            promptTokens: inTokens, completionTokens: tok(output),
            cacheHitTokens: 0, cacheMissTokens: inTokens
        )
        record(usage: usage, model: model)
    }
}
