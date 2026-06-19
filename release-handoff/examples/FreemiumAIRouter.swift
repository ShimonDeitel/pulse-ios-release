//
//  FreemiumAIRouter.swift
//
//  Drop-in module: tiered AI access with a paid "Primary Access" lane and a
//  free-provider failover waterfall.
//
//  ⚠️ SECURITY — read before shipping:
//  Any API key compiled into an iOS binary can be extracted in minutes
//  (`strings`, class-dump). For production, keep provider keys on a tiny
//  server proxy (e.g. a Cloudflare Worker) and point the providers below at
//  YOUR endpoint — the app then carries only a revocable session token.
//  The `YourAPIKeys` placeholders are for development / proxy-backed setups.
//

import SwiftUI
import Observation

// MARK: - API Keys (fill these in)

enum YourAPIKeys {
    /// PAID Google AI key — premium traffic only (Gemini 2.5 Flash).
    static let geminiPaid = "YOUR_PAID_GEMINI_KEY"
    /// Free-tier Google AI Studio key (separate project/key from the paid one,
    /// so free traffic can never bill the paid account).
    static let googleAIStudioFree = "YOUR_FREE_AI_STUDIO_KEY"
    /// OpenRouter key used only with ":free" routed models.
    static let openRouterFree = "YOUR_OPENROUTER_KEY"
    /// Cerebras Cloud free-tier key.
    static let cerebrasFree = "YOUR_CEREBRAS_KEY"
}

// MARK: - 1. User Tier

enum UserTier: String, Codable, Sendable {
    case free
    case paid

    /// Goal allowance per tier. `nil` = unlimited.
    var maxGoals: Int? {
        switch self {
        case .free: return 1
        case .paid: return nil
        }
    }
}

/// Single source of truth for the user's tier and how many goals they've made.
/// `@Observable` + `@MainActor` keeps every SwiftUI view in sync automatically.
@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private(set) var tier: UserTier = .free
    private(set) var goalsCreated: Int

    private init() {
        // Persisted locally so the free-tier cap survives relaunch. In a real
        // app, derive this from your data store (Core Data/SwiftData) instead,
        // so deleting/reinstalling can't reset the count via UserDefaults.
        goalsCreated = UserDefaults.standard.integer(forKey: "goalsCreated")
    }

    var isPaid: Bool { tier == .paid }

    /// True when the user may create one more goal (Free: 1 max, Paid: ∞).
    var canCreateGoal: Bool {
        guard let cap = tier.maxGoals else { return true }
        return goalsCreated < cap
    }

    /// Record a successfully created goal.
    func registerGoalCreated() {
        goalsCreated += 1
        UserDefaults.standard.set(goalsCreated, forKey: "goalsCreated")
    }

    /// Call this ONLY from your StoreKit 2 flow after a VERIFIED transaction:
    /// iterate `Transaction.currentEntitlements`, check `productID` matches
    /// your $10 premium product, verify, then flip the tier here.
    func applyEntitlement(isPremium: Bool) {
        tier = isPremium ? .paid : .free
    }
}

// MARK: - 2. Provider Abstraction

/// Errors a single provider attempt can produce. The router treats every one
/// of these as "move down the waterfall".
enum AIProviderError: Error {
    case rateLimited            // HTTP 429 — quota/queue exhausted
    case serverError(Int)       // 5xx or unexpected status — provider down
    case badResponse            // 2xx but unparseable/empty body
    case transport(Error)       // URLSession-level failure (offline, timeout, DNS)
}

/// One AI backend. Each conforming type performs exactly ONE network round trip.
protocol AIProvider: Sendable {
    var name: String { get }
    func generate(prompt: String, systemPrompt: String?) async throws -> String
}

// MARK: Google Gemini provider (paid AND free — same wire format, different key/model)

struct GeminiProvider: AIProvider {
    let name: String
    let model: String       // "gemini-2.5-flash" (paid) / "gemini-2.5-flash-lite" (free)
    let apiKey: String

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        // ────────────────────────────────────────────────────────────────
        // NETWORK REQUEST #1 happens here: Gemini REST `generateContent`.
        // Swap this block for the GoogleGenerativeAI SDK if you prefer.
        // ────────────────────────────────────────────────────────────────
        guard let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")
        else { throw AIProviderError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]]
        ]
        if let systemPrompt {
            body["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // URLSession surfaces task cancellation as URLError(.cancelled),
            // NOT Swift's CancellationError. Normalise it so the router stops
            // the waterfall instead of treating it as a provider outage.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw AIProviderError.transport(error)
        }
        try Self.checkHTTPStatus(response)

        // Minimal parse: candidates[0].content.parts[*].text
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else { throw AIProviderError.badResponse }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIProviderError.badResponse }
        return text
    }

    static func checkHTTPStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.badResponse }
        switch http.statusCode {
        case 200...299: return
        case 429:       throw AIProviderError.rateLimited
        default:        throw AIProviderError.serverError(http.statusCode)
        }
    }
}

// MARK: OpenAI-compatible provider (OpenRouter, Cerebras, Groq, …)

struct OpenAICompatibleProvider: AIProvider {
    let name: String
    let baseURL: URL        // e.g. https://openrouter.ai/api/v1
    let model: String       // e.g. "meta-llama/llama-3.3-70b-instruct:free"
    let apiKey: String

    func generate(prompt: String, systemPrompt: String?) async throws -> String {
        // ────────────────────────────────────────────────────────────────
        // NETWORK REQUEST #2 happens here: OpenAI-style `/chat/completions`.
        // Works unchanged for OpenRouter, Cerebras, Groq — only baseURL,
        // model, and key differ.
        // ────────────────────────────────────────────────────────────────
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        var messages: [[String: String]] = []
        if let systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages
        ] as [String: Any])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // URLSession reports cancellation as URLError(.cancelled), not
            // CancellationError — normalise so the router can stop cleanly.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw AIProviderError.transport(error)
        }
        try GeminiProvider.checkHTTPStatus(response)

        // Minimal parse: choices[0].message.content
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = message["content"] as? String,
            !text.isEmpty
        else { throw AIProviderError.badResponse }

        return text
    }
}

// MARK: - 3. The LLM Failover Router (core engine)

enum AIRouterError: LocalizedError {
    /// Every provider in the chain failed.
    case allProvidersBusy

    var errorDescription: String? {
        switch self {
        case .allProvidersBusy:
            return "A lot of users are using the app right now. Please try again later."
        }
    }
}

final class AIRouterService: Sendable {
    static let shared = AIRouterService()

    /// PAID lane ("Primary Access"): premium model first, one free emergency backup.
    private let paidChain: [any AIProvider]
    /// FREE lane: the failover waterfall, ordered cheapest-tokens / fastest-queue first.
    private let freeChain: [any AIProvider]

    init() {
        // Premium: Gemini 2.5 Flash on the PAID key.
        let geminiPaid = GeminiProvider(
            name: "Gemini 2.5 Flash (paid)",
            model: "gemini-2.5-flash",
            apiKey: YourAPIKeys.geminiPaid)

        // Free waterfall — order matters:
        //   1. AI Studio free tier: lightest model, generous free quota.
        //   2. Cerebras free tier: very fast inference, good fallback queue.
        //   3. OpenRouter ":free" models: broad catalog, last resort.
        let aiStudioFree = GeminiProvider(
            name: "AI Studio (free)",
            model: "gemini-2.5-flash-lite",
            apiKey: YourAPIKeys.googleAIStudioFree)
        let cerebrasFree = OpenAICompatibleProvider(
            name: "Cerebras (free)",
            baseURL: URL(string: "https://api.cerebras.ai/v1")!,
            model: "llama-3.3-70b",
            apiKey: YourAPIKeys.cerebrasFree)
        let openRouterFree = OpenAICompatibleProvider(
            name: "OpenRouter (free)",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            model: "meta-llama/llama-3.3-70b-instruct:free",
            apiKey: YourAPIKeys.openRouterFree)

        freeChain = [aiStudioFree, cerebrasFree, openRouterFree]
        // Paid users skip every free queue; if the premium model itself is
        // down, they silently fall back to the best free provider rather
        // than seeing an error.
        paidChain = [geminiPaid, aiStudioFree]
    }

    /// Generate text for the given tier.
    ///
    /// PAID → premium model immediately, free backup only on failure.
    /// FREE → Step 1: cheapest/fastest free provider.
    ///        Step 2: on ANY failure (429, 5xx, offline, bad body) → next provider.
    ///        Step 3: all failed → friendly "try again later" error.
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        tier: UserTier
    ) async throws -> String {
        let chain = (tier == .paid) ? paidChain : freeChain

        for provider in chain {
            // Stop the whole waterfall the instant the caller cancels (e.g. the
            // user left the screen) — never probe additional providers, and
            // never let a cancellation masquerade as "all providers busy".
            try Task.checkCancellation()
            do {
                let text = try await provider.generate(prompt: prompt, systemPrompt: systemPrompt)
                return text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Rate-limited, server down, transport error, bad body:
                // log and cascade to the next provider in the waterfall.
                #if DEBUG
                print("[AIRouter] \(provider.name) failed: \(error) — trying next provider")
                #endif
                continue
            }
        }
        // Step 3: nothing left to try.
        throw AIRouterError.allProvidersBusy
    }
}

// MARK: - 4. SwiftUI example

/// Demonstrates the full gate sequence:
///   1. Free user with 1 goal taps "Create" → paywall sheet (no network call).
///   2. Otherwise the prompt routes by tier: paid → premium lane, free → waterfall.
///   3. All-providers-down surfaces the friendly busy message.
struct GoalCreationView: View {
    @State private var subscriptions = SubscriptionManager.shared

    @State private var goalText = ""
    @State private var aiPlan: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showPaywall = false
    /// Held so the in-flight request is cancelled if the user leaves the screen.
    @State private var generationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("New goal") {
                    TextField("e.g. Run a 10k in 8 weeks", text: $goalText)
                    Button {
                        createGoalTapped()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Create goal with AI")
                        }
                    }
                    .disabled(goalText.isEmpty || isLoading)
                }

                if let aiPlan {
                    Section("Your AI plan") { Text(aiPlan) }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section("Account") {
                    LabeledContent("Tier", value: subscriptions.isPaid ? "Pro ⭐️" : "Free")
                    LabeledContent("Goals created", value: "\(subscriptions.goalsCreated)")
                }
            }
            .navigationTitle("Goals")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onDisappear { generationTask?.cancel() }
        }
    }

    private func createGoalTapped() {
        // GATE 1 — goal allowance. A free user's SECOND goal never reaches
        // the network: it opens the paywall instead.
        guard subscriptions.canCreateGoal else {
            showPaywall = true
            return
        }

        isLoading = true
        errorMessage = nil
        aiPlan = nil

        generationTask?.cancel()      // supersede any prior in-flight request
        generationTask = Task {
            defer { isLoading = false }
            do {
                // GATE 2 — tier routing. Paid → Primary Access (premium model),
                // Free → the free-provider waterfall.
                let plan = try await AIRouterService.shared.generate(
                    prompt: "Create a short, step-by-step plan for this goal: \(goalText)",
                    systemPrompt: "You are a concise, encouraging goal coach.",
                    tier: subscriptions.tier)
                aiPlan = plan
                // Only a delivered result consumes the free tier's single slot.
                subscriptions.registerGoalCreated()
            } catch is CancellationError {
                // User left the screen mid-request — abandon silently and,
                // crucially, do NOT consume the goal allowance.
            } catch {
                // AIRouterError.allProvidersBusy renders as the friendly
                // "A lot of users are using the app right now…" message.
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Minimal $10 paywall. Wire the button to your real StoreKit 2 purchase.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Go Premium").font(.largeTitle.bold())
            Text("Primary Access: instant premium AI, no queues,\nand unlimited goals.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                // StoreKit 2 purchase happens here:
                //   let result = try await premiumProduct.purchase()
                //   → verify the transaction, finish() it, THEN:
                SubscriptionManager.shared.applyEntitlement(isPremium: true)
                dismiss()
            } label: {
                Text("Unlock for $10")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Not now") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

#Preview {
    GoalCreationView()
}
