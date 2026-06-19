import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AppleOnDeviceLLM
//
// FREE, private, on-device text generation via Apple's Foundation Models
// framework (iOS 26+, Apple-Intelligence-capable devices — iPhone 15 Pro and
// later). Used as the PREFERRED engine for light conversational turns (the mentor
// one-shot chat). Anything it can't do — older OS, ineligible device, model not
// ready, or any runtime error — falls through to the cloud router automatically.
//
// Deliberately NOT used for: heavy structured/JSON generation (roadmaps, plans)
// or vision (meal photos) — those stay on cloud Gemini for quality. On-device
// calls cost nothing, so AIRouter records no spend for them.
//
// The whole file is guarded by `canImport(FoundationModels)` so it compiles even
// on toolchains without the framework; on those it simply reports unavailable.
enum AppleOnDeviceLLM {

    struct Unavailable: Error {}

    /// True only when the on-device model can actually run a request right now
    /// (framework present, iOS 26+, eligible device, Apple Intelligence enabled,
    /// model downloaded). Cheap to call.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Run one conversational turn fully on-device. Prior turns are folded into
    /// the instructions so we don't depend on transcript-seeding APIs. Throws
    /// `Unavailable` (or any model error) so the caller can fall back to cloud.
    static func generate(
        systemPrompt: String?,
        userMessage: String,
        history: [(role: String, content: String)]
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw Unavailable()
            }

            var instructions = systemPrompt ?? "You are a helpful, knowledgeable coach."
            if !history.isEmpty {
                let convo = history.suffix(8)
                    .map { "\($0.role == "user" ? "User" : "Coach"): \($0.content)" }
                    .joined(separator: "\n")
                instructions += "\n\nConversation so far:\n\(convo)"
            }

            let session = LanguageModelSession {
                instructions
            }
            let response = try await session.respond(to: userMessage)
            return response.content
        }
        #endif
        throw Unavailable()
    }
}
