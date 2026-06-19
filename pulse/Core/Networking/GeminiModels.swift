import Foundation

// MARK: - Gemini API Request
struct GeminiRequest: Codable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?
    let systemInstruction: GeminiContent?

    init(contents: [GeminiContent], systemInstruction: GeminiContent? = nil, generationConfig: GeminiGenerationConfig? = nil) {
        self.contents = contents
        self.systemInstruction = systemInstruction
        self.generationConfig = generationConfig
    }
}

struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]

    init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

struct GeminiPart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(inlineData: GeminiInlineData) {
        self.text = nil
        self.inlineData = inlineData
    }
}

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String  // base64
}

struct GeminiGenerationConfig: Codable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let responseMimeType: String?

    init(temperature: Double? = 0.7, maxOutputTokens: Int? = 4096, responseMimeType: String? = nil) {
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.responseMimeType = responseMimeType
    }
}

// MARK: - Gemini API Response
struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]?
    let error: GeminiError?
}

struct GeminiCandidate: Codable {
    let content: GeminiContent?
    let finishReason: String?
}

struct GeminiError: Codable {
    let code: Int?
    let message: String?
    let status: String?
}

// MARK: - Helpers
extension GeminiResponse {
    var text: String? {
        candidates?.first?.content?.parts.first?.text
    }
}
