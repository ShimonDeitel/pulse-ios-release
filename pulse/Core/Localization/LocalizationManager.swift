import SwiftUI

// MARK: - Localization Manager
// Comprehensive multi-language support with instant switching.
// Uses Gemini AI for runtime translation with aggressive caching.
// All UI text goes through `L10n.t("key")` for dynamic language updates.

@Observable
class LocalizationManager {
    static let shared = LocalizationManager()

    /// All translated strings keyed by their English source
    private(set) var translations: [String: String] = [:]

    /// Whether translations are currently loading
    var isTranslating = false

    /// Revision counter to trigger SwiftUI updates
    var revision: Int = 0

    /// LANGUAGE FEATURE REMOVED — English-only. Hardcoded.
    /// Setter is a no-op so existing callers compile but cannot change it.
    var targetLanguage: String {
        get { "en" }
        set { /* English-only build */ }
    }

    /// The full language name for the current target
    var currentLanguageName: String {
        SupportedLanguage.allCases.first { $0.code == targetLanguage }?.displayName ?? "English"
    }

    /// Cache key for stored translations
    private func cacheKey(for language: String) -> String {
        "pulse_translations_v2_\(language)"
    }

    /// Get a translated string, falling back to English
    func t(_ key: String) -> String {
        if targetLanguage == "en" { return key }
        return translations[key] ?? key
    }

    /// Load cached translations on launch
    func loadCachedTranslations() {
        let lang = targetLanguage
        guard lang != "en" else { return }

        if let cached = UserDefaults.standard.dictionary(forKey: cacheKey(for: lang)) as? [String: String], !cached.isEmpty {
            translations = cached
            revision += 1
            return
        }

        // Fall back to bundled instant translations for top languages
        if let bundled = BundledTranslations.dictionary(for: lang) {
            translations = bundled
            UserDefaults.standard.set(bundled, forKey: cacheKey(for: lang))
            revision += 1
            return
        }

        Task { await translateAllStrings(to: lang) }
    }

    /// LANGUAGE FEATURE REMOVED — no-op. English only.
    func switchLanguage(to languageCode: String) { /* English-only build */ }

    /// Translate all app strings using Gemini AI
    func translateAllStrings(to languageCode: String) async {
        guard !isTranslating else { return }

        await MainActor.run { isTranslating = true }

        // Check cache first
        if let cached = UserDefaults.standard.dictionary(forKey: cacheKey(for: languageCode)) as? [String: String], cached.count >= AppStrings.all.count - 5 {
            await MainActor.run {
                translations = cached
                isTranslating = false
                revision += 1
            }
            return
        }

        do {
            let langName = SupportedLanguage.allCases.first { $0.code == languageCode }?.englishName ?? languageCode

            // Translate in batches via Gemini
            var newTranslations: [String: String] = [:]
            let batchSize = 40

            for batchStart in stride(from: 0, to: AppStrings.all.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, AppStrings.all.count)
                let batch = Array(AppStrings.all[batchStart..<batchEnd])

                let numberedStrings = batch.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

                let prompt = """
                Translate these English UI strings to \(langName). Return ONLY the translations, one per line, numbered exactly like the input. Keep them short and natural for mobile UI labels. Do NOT add explanations or extra text.

                \(numberedStrings)
                """

                let response = try await GeminiAPIService.shared.sendMessage(
                    userMessage: prompt,
                    systemPrompt: "You are a professional app translator. Translate UI text precisely and naturally for mobile apps. Return only numbered translations, one per line. Never add notes or explanations.",
                    temperature: 0.2,
                    maxTokens: 4096
                )

                // Parse numbered responses
                let lines = response.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for (index, line) in lines.enumerated() {
                    if index < batch.count {
                        // Strip numbering prefix like "1. " or "1) "
                        var translated = line
                        if let dotRange = translated.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                            translated = String(translated[dotRange.upperBound...])
                        }
                        newTranslations[batch[index]] = translated.trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            // Cache the translations
            UserDefaults.standard.set(newTranslations, forKey: cacheKey(for: languageCode))

            await MainActor.run {
                translations = newTranslations
                isTranslating = false
                revision += 1
            }
        } catch {
            print("Translation error: \(error)")
            await MainActor.run { isTranslating = false }
        }
    }

    /// Force re-translate (clears cache for current language)
    func retranslate() {
        let lang = targetLanguage
        guard lang != "en" else { return }
        UserDefaults.standard.removeObject(forKey: cacheKey(for: lang))
        translations = [:]
        Task { await translateAllStrings(to: lang) }
    }

    /// Clear all cached translations
    func clearCache() {
        let languages = SupportedLanguage.allCases.map(\.code)
        for lang in languages {
            UserDefaults.standard.removeObject(forKey: cacheKey(for: lang))
        }
        translations = [:]
        revision += 1
    }

    /// Language instruction for AI system prompts
    var aiLanguageInstruction: String {
        let lang = targetLanguage
        if lang == "en" { return "" }
        let langName = SupportedLanguage.allCases.first { $0.code == lang }?.englishName ?? lang
        return """


        =================== LANGUAGE DIRECTIVE ===================
        The user's app language is set to \(langName).
        You MUST respond entirely in \(langName).
        Every word — greetings, instructions, encouragement, feedback,
        technical terms, brand references — must be written naturally
        and fluently in \(langName).
        Do NOT translate the user's goal title literally; instead write
        about it naturally in \(langName).
        Do NOT include any English text unless quoting something the
        user wrote in English themselves.
        ==========================================================
        """
    }
}

// MARK: - Convenience Type Alias
typealias L10n = LocalizationManager

// MARK: - All App Strings (English source of truth)
// Every user-facing string in the app should be listed here.

struct AppStrings {
    static let all: [String] = [
        // Tab bar
        "Home", "Goals", "Chat", "Mentor", "Profile",

        // Dashboard
        "pulse", "No active goals",
        "Set your first goal and let Pulse build\nyour roadmap to achievement.",
        "New Goal", "Active Goals", "Insights", "Other goals",
        "Today's pulses", "ACTIVE GOAL", "COMPLETE",
        "PULSES", "DAYS LEFT",

        // Greeting
        "All clear today,", "One pulse today,",
        "then you're ahead.", "you're ahead.",
        "Good morning,", "Good afternoon,", "Good evening,", "Good night,",
        "pulses today,",

        // Goal Input
        "What's your goal?", "GOAL TITLE", "CATEGORY",
        "DEADLINE", "MOTIVATION", "Your Resources",
        "TIME PER DAY", "SKILL LEVEL", "CURRENT PROGRESS",
        "Potential Obstacles", "What might get in your way?",
        "COMMON OBSTACLES", "Cancel", "Back", "Next", "Analyze",
        "Start Mission", "AI is building your roadmap...",
        "Analysis Failed", "Retry", "Success Probability",
        "Assessment", "Fastest Path", "Your Roadmap", "Skill Gaps",
        "What did you do so far?", "What do you need help with?",
        "Progress Context",

        // Categories
        "Fitness", "Learning", "Finance", "Career", "Health",
        "Creative", "Social", "Mindfulness", "Personal",

        // Skill Levels
        "Beginner", "Intermediate", "Advanced", "Expert",

        // Obstacles
        "Time management", "Lack of motivation", "Budget constraints",
        "Skill gaps", "Procrastination", "External commitments",
        "Fear of failure", "Perfectionism", "Inconsistent schedule",
        "Lack of accountability", "Information overload", "Physical fatigue",
        "Social pressure", "Self-doubt", "Distractions at home",
        "Unclear next steps",

        // Goal Detail
        "NEXT PULSE", "All Pulses Complete!",
        "You've completed every pulse in your roadmap",
        "pulses complete", "days left",
        "Rename", "Delete", "Edit Goal",

        // Roadmap
        "Pulse Verified!", "Not Yet Complete",
        "Pulse marked complete!", "Submit Proof",
        "Describe your proof", "Verify with AI",
        "Mark Complete", "Proof needed:",
        "Upload Proof",

        // Mentor
        "Mentor", "Message your mentor...", "Send",
        "Coach", "Drill Sergeant", "Supportive", "Aggressive",
        "Brutally Honest", "Minimalist", "High Energy",
        "Calm", "Disciplined", "Friendly",

        // Profile / Settings
        "Profile", "Settings", "Personal info", "Notifications",
        "Privacy", "Appearance", "Language", "Region",
        "Help & FAQ", "About Pulse", "Sign Out",
        "System", "Light", "Dark",
        "Account", "Preferences", "Support",
        "AI Settings", "Subscription",


        // Focus
        "Focus Timer", "Start Focus", "minutes",

        // Achievements
        "Achievements", "Level", "XP",

        // Photo Transformation
        "Photo Transformation", "Take Photo", "Choose from Library",

        // Common
        "Done", "Save", "Delete", "Edit", "Close", "OK",
        "Loading...", "Error", "Success", "Confirm",

        // Notifications
        "Pulse Check-In",
        "Don't break your streak!",
        "Time to focus on your goal",

        // Onboarding
        "Get Started", "Continue", "Skip",
        "Welcome to Pulse", "Your AI-powered goal engine",
        "Set a goal. Get a plan. Execute daily.",

        // Widgets
        "Goal Progress", "Streak", "Next Pulse",

        // New Goal / Detail
        "New Goal", "Active", "Completed", "Paused",
        "days remaining", "probability",

        // Language Picker
        "Search languages", "Select Language",
    ]
}

// MARK: - Supported Languages

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case hebrew = "Hebrew"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case arabic = "Arabic"
    case russian = "Russian"
    case portuguese = "Portuguese"
    case japanese = "Japanese"
    case korean = "Korean"
    case chinese = "Chinese"
    case italian = "Italian"
    case turkish = "Turkish"
    case hindi = "Hindi"
    case dutch = "Dutch"
    case polish = "Polish"
    case thai = "Thai"
    case indonesian = "Indonesian"
    case ukrainian = "Ukrainian"
    case vietnamese = "Vietnamese"

    var id: String { code }

    /// Display name in the language's own script
    var displayName: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "\u{05E2}\u{05D1}\u{05E8}\u{05D9}\u{05EA}"          // עברית
        case .spanish: return "Espa\u{00F1}ol"                                    // Español
        case .french: return "Fran\u{00E7}ais"                                    // Français
        case .german: return "Deutsch"
        case .arabic: return "\u{0627}\u{0644}\u{0639}\u{0631}\u{0628}\u{064A}\u{0629}"  // العربية
        case .russian: return "\u{0420}\u{0443}\u{0441}\u{0441}\u{043A}\u{0438}\u{0439}" // Русский
        case .portuguese: return "Portugu\u{00EA}s"                               // Português
        case .japanese: return "\u{65E5}\u{672C}\u{8A9E}"                         // 日本語
        case .korean: return "\u{D55C}\u{AD6D}\u{C5B4}"                           // 한국어
        case .chinese: return "\u{4E2D}\u{6587}"                                  // 中文
        case .italian: return "Italiano"
        case .turkish: return "T\u{00FC}rk\u{00E7}e"                              // Türkçe
        case .hindi: return "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}"    // हिन्दी
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .thai: return "\u{0E44}\u{0E17}\u{0E22}"                             // ไทย
        case .indonesian: return "Bahasa Indonesia"
        case .ukrainian: return "\u{0423}\u{043A}\u{0440}\u{0430}\u{0457}\u{043D}\u{0441}\u{044C}\u{043A}\u{0430}"  // Українська
        case .vietnamese: return "Ti\u{1EBF}ng Vi\u{1EC7}t"                       // Tiếng Việt
        }
    }

    /// English name (for AI prompts and search)
    var englishName: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "Hebrew"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .arabic: return "Arabic"
        case .russian: return "Russian"
        case .portuguese: return "Portuguese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chinese: return "Chinese"
        case .italian: return "Italian"
        case .turkish: return "Turkish"
        case .hindi: return "Hindi"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .thai: return "Thai"
        case .indonesian: return "Indonesian"
        case .ukrainian: return "Ukrainian"
        case .vietnamese: return "Vietnamese"
        }
    }

    var code: String {
        switch self {
        case .english: return "en"
        case .hebrew: return "he"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .arabic: return "ar"
        case .russian: return "ru"
        case .portuguese: return "pt"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .chinese: return "zh"
        case .italian: return "it"
        case .turkish: return "tr"
        case .hindi: return "hi"
        case .dutch: return "nl"
        case .polish: return "pl"
        case .thai: return "th"
        case .indonesian: return "id"
        case .ukrainian: return "uk"
        case .vietnamese: return "vi"
        }
    }

    /// ISO language code abbreviation (replaces flag emojis)
    var abbreviation: String {
        code.uppercased()
    }
}

// MARK: - View Extension for Translation

extension View {
    /// Translates a string using the shared LocalizationManager
    func translated(_ text: String) -> String {
        LocalizationManager.shared.t(text)
    }
}

// MARK: - String Extension for Translation

extension String {
    /// LANGUAGE FEATURE REMOVED — English-only build. Returns self.
    /// Kept on the type so the (hundreds of) existing `.localized` call sites
    /// keep compiling without touching every view.
    var localized: String { self }
}
