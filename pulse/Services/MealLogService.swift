import Foundation
import UIKit
import CoreData

/// Logs meals (text or photo) and tallies macros against the user's daily targets.
/// Photos are sent to the vision model for analysis, then results are stored
/// per-day in UserDefaults so they survive restarts and reset at midnight.
@Observable
@MainActor
final class MealLogService {
    static let shared = MealLogService()
    private init() {}

    // MARK: - Photo storage (so meals can be re-analyzed after correction)

    /// Documents/meal_photos — original meal JPEGs live here, keyed by UUID filename.
    /// @ObservationIgnored: internal storage, not observable UI state — and `lazy`
    /// is incompatible with the @Observable macro's tracked-property rewrite.
    @ObservationIgnored private lazy var photosDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("meal_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Persist a meal JPEG and return its filename, or nil on failure.
    private func savePhoto(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: photosDir.appendingPathComponent(name))
            return name
        } catch { return nil }
    }

    /// Load a previously stored meal JPEG as Data.
    private func loadPhotoData(_ name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: photosDir.appendingPathComponent(name))
    }

    /// Remove a stored meal JPEG (called when its entry is deleted).
    private func deletePhotoFile(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: photosDir.appendingPathComponent(name))
    }

    // MARK: - Persisted entries

    /// All meals logged today.
    private(set) var todayEntries: [MealEntry] = []
    var isAnalyzing = false
    var lastError: String?

    /// The yyyy-MM-dd that `todayEntries` currently represents. Used to detect a
    /// midnight rollover when the app is left foregrounded across days.
    private var loadedDay: String?

    /// Today's yyyy-MM-dd (recomputed each access from the wall clock).
    private var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var todayKey: String { "pulse_meals_\(dayString)" }

    func load() {
        let day = dayString
        loadedDay = day
        guard let data = UserDefaults.standard.data(forKey: "pulse_meals_\(day)"),
              let decoded = try? JSONDecoder().decode([MealEntry].self, from: data) else {
            todayEntries = []
            return
        }
        todayEntries = decoded
    }

    /// If the calendar day has advanced since `todayEntries` was loaded, reload
    /// from the new day's key (recomputing `todayKey`). Call this before reading
    /// or appending so a screen left open across midnight logs to the right day.
    private func rolloverIfNeeded() {
        if loadedDay != dayString { load() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(todayEntries) {
            UserDefaults.standard.set(data, forKey: todayKey)
        }
    }

    // MARK: - Public API

    func deleteEntry(_ entry: MealEntry) {
        rolloverIfNeeded()
        deletePhotoFile(entry.photoFilename)
        todayEntries.removeAll { $0.id == entry.id }
        persist()
    }

    /// Today's running totals across all logged meals.
    var totalsToday: DailyMacros {
        rolloverIfNeeded()
        return DailyMacros(
            calories: todayEntries.reduce(0) { $0 + $1.calories },
            proteinGrams: todayEntries.reduce(0) { $0 + $1.proteinGrams },
            carbsGrams: todayEntries.reduce(0) { $0 + $1.carbsGrams },
            fatGrams: todayEntries.reduce(0) { $0 + $1.fatGrams }
        )
    }

    /// Analyze a meal photo via vision AI and add it to today's log.
    func logMealFromPhoto(_ image: UIImage, userNote: String?) async {
        isAnalyzing = true
        lastError = nil
        defer { isAnalyzing = false }

        guard let data = image.jpegData(compressionQuality: 0.6) else {
            lastError = "Couldn't read photo"
            return
        }

        let userPrompt = """
        Look at this meal photo and estimate the nutrition for ONE person's serving.
        If the photo is unclear, low light, or doesn't clearly show food, make your
        best realistic guess — DO NOT refuse to answer.
        \(userNote.map { "\nThe user added a note (trust it as ground truth about WHAT the food is): \($0)" } ?? "")

        \(Self.nutritionMethod)

        Output ONLY raw JSON. No code fences, no prose before or after. Start with `{` and end with `}`.
        Schema:
        \(Self.nutritionSchema)
        """

        do {
            let raw = try await GeminiAPIService.shared.sendVisionMessage(
                textPrompt: userPrompt,
                images: [(data: data, mimeType: "image/jpeg")],
                systemPrompt: Self.nutritionSystem,
                temperature: 0.2,
                maxTokens: 700
            )
            let cleaned = stripFences(raw)
            guard let jsonData = cleaned.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(MealEntryWire.self, from: jsonData) else {
                lastError = "AI returned an unreadable response"
                return
            }
            let parsed = reconcile(decoded)
            guard isUsable(parsed) else {
                lastError = "AI returned an unreadable response"
                return
            }
            let savedName = savePhoto(data)
            let entry = MealEntry(
                id: UUID(),
                loggedAt: Date(),
                name: parsed.name,
                calories: parsed.calories,
                proteinGrams: parsed.proteinGrams,
                carbsGrams: parsed.carbsGrams,
                fatGrams: parsed.fatGrams,
                confidence: parsed.confidence,
                notes: parsed.notes,
                source: .photo,
                photoFilename: savedName
            )
            // The vision call above can span midnight; make sure we append to the
            // current day's log (and persist under today's key) if it has.
            rolloverIfNeeded()
            todayEntries.append(entry)
            persist()
            Task.detached(priority: .utility) {
                try? await FirestoreSyncService.shared.syncMealEntry(entry)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Log a meal from a text description (fallback when no photo).
    func logMealFromText(_ description: String) async {
        isAnalyzing = true
        lastError = nil
        defer { isAnalyzing = false }

        let system = """
        \(Self.nutritionSystem)

        The user describes a meal in plain text; estimate ONE typical serving.
        \(Self.nutritionMethod)

        Return ONLY valid JSON in this schema:
        \(Self.nutritionSchema)
        """
        do {
            let raw = try await AIRouter.shared.sendMessage(
                userMessage: "Meal: \(description)",
                systemPrompt: system,
                temperature: 0.2,
                maxTokens: 600
            )
            let cleaned = stripFences(raw)
            guard let jsonData = cleaned.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(MealEntryWire.self, from: jsonData) else {
                lastError = "AI returned an unreadable response"
                return
            }
            let parsed = reconcile(decoded)
            guard isUsable(parsed) else {
                lastError = "AI returned an unreadable response"
                return
            }
            let entry = MealEntry(
                id: UUID(),
                loggedAt: Date(),
                name: parsed.name,
                calories: parsed.calories,
                proteinGrams: parsed.proteinGrams,
                carbsGrams: parsed.carbsGrams,
                fatGrams: parsed.fatGrams,
                confidence: parsed.confidence,
                notes: parsed.notes,
                source: .text
            )
            // The estimate call above can span midnight; make sure we append to the
            // current day's log (and persist under today's key) if it has.
            rolloverIfNeeded()
            todayEntries.append(entry)
            persist()
            Task.detached(priority: .utility) {
                try? await FirestoreSyncService.shared.syncMealEntry(entry)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-analyze an existing meal entry using the user's correction as ground
    /// truth. If the original photo is still on disk, re-runs vision on that exact
    /// image; otherwise re-estimates from text. Replaces the entry's
    /// name/macros/confidence/notes in place (id + loggedAt + source preserved).
    func correctEntry(_ entry: MealEntry, userSaysItIs correction: String) async {
        let trimmed = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rolloverIfNeeded()
        guard todayEntries.contains(where: { $0.id == entry.id }) else { return }

        isAnalyzing = true
        lastError = nil
        defer { isAnalyzing = false }

        // Include any prior correction so the model has the full history
        // (lightweight "learning" — it sees what it got wrong before).
        let priorContext: String = {
            if let prev = entry.correctionNote, !prev.isEmpty {
                return "The user previously corrected this to: \"\(prev)\". They now say: \"\(trimmed)\"."
            }
            return "The user says this is actually: \"\(trimmed)\"."
        }()

        var parsed: MealEntryWire?
        let photoData = loadPhotoData(entry.photoFilename)

        if let data = photoData {
            // Re-run VISION on the same photo, correction as authoritative.
            let userPrompt = """
            Re-estimate the nutrition for this meal photo for ONE person's serving.
            \(priorContext)
            Treat the user's description as authoritative ground truth about WHAT
            the food is — trust it over your own visual guess if they conflict —
            but use the photo for portion size. DO NOT refuse.

            \(Self.nutritionMethod)

            Output ONLY raw JSON. No code fences, no prose before or after. Start with `{` and end with `}`.
            Schema:
            \(Self.nutritionSchema)
            """
            do {
                let raw = try await GeminiAPIService.shared.sendVisionMessage(
                    textPrompt: userPrompt,
                    images: [(data: data, mimeType: "image/jpeg")],
                    systemPrompt: Self.nutritionSystem,
                    temperature: 0.2,
                    maxTokens: 700
                )
                let cleaned = stripFences(raw)
                parsed = cleaned.data(using: .utf8).flatMap { try? JSONDecoder().decode(MealEntryWire.self, from: $0) }
            } catch {
                lastError = error.localizedDescription
                return
            }
        } else {
            // No stored photo (text log, or pre-update entry) — re-estimate from text.
            let system = """
            \(Self.nutritionSystem)

            Estimate ONE typical serving of the meal the user describes.
            \(Self.nutritionMethod)

            Return ONLY valid JSON in this schema:
            \(Self.nutritionSchema)
            """
            do {
                let raw = try await AIRouter.shared.sendMessage(
                    userMessage: "Meal: \(trimmed)",
                    systemPrompt: system,
                    temperature: 0.2,
                    maxTokens: 600
                )
                let cleaned = stripFences(raw)
                parsed = cleaned.data(using: .utf8).flatMap { try? JSONDecoder().decode(MealEntryWire.self, from: $0) }
            } catch {
                lastError = error.localizedDescription
                return
            }
        }

        guard let decoded = parsed else {
            lastError = "AI returned an unreadable response"
            return
        }
        let p = reconcile(decoded)
        guard isUsable(p) else {
            lastError = "AI returned an unreadable response"
            return
        }

        // Defensive re-lookup: todayEntries could have changed during the await.
        guard let liveIdx = todayEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = todayEntries[liveIdx]
        updated.name = p.name
        updated.calories = p.calories
        updated.proteinGrams = p.proteinGrams
        updated.carbsGrams = p.carbsGrams
        updated.fatGrams = p.fatGrams
        updated.confidence = p.confidence
        updated.notes = p.notes
        updated.correctionNote = trimmed
        todayEntries[liveIdx] = updated
        persist()
        let synced = updated
        Task.detached(priority: .utility) {
            try? await FirestoreSyncService.shared.syncMealEntry(synced)
        }
    }

    // MARK: - Nutrition estimation guidance (shared across every prompt)

    /// The estimation METHOD injected into every nutrition prompt. Forcing the
    /// model to (1) enumerate each component + its portion, (2) include the
    /// easy-to-miss added fats, (3) use standard reference values, and (4) make
    /// calories EQUAL 4·protein + 4·carbs + 9·fat produces numbers that are both
    /// more accurate and internally consistent. The cheap vision model, left to
    /// its own devices, throws out calories that don't match its own macros —
    /// which is exactly what reads as "way off".
    static let nutritionMethod = """
    ESTIMATION METHOD — follow every step, and aim for the MOST LIKELY real value. Do NOT inflate.
    1. Identify only the components that are actually there: the protein, the carb/starch, \
    vegetables, and extras ONLY when clearly present or implied (sauce, dressing, cheese, frying oil). \
    Do NOT invent oil, butter, or sauces — a grilled, baked, steamed, boiled, or plain dish carries \
    very little added fat.
    2. Estimate each portion realistically. For a photo, judge scale from the plate/utensils; for a \
    described meal, use ONE normal serving of exactly what the user described — nothing extra.
    3. Apply standard nutrition values. Per 100g cooked: chicken breast 165kcal/31P/0C/4F; \
    white rice 130kcal/2.7P/28C/0.3F; pasta 158kcal/6P/31C/1F; ground beef 80/20 250kcal/26P/0C/15F; \
    salmon 208kcal/20P/0C/13F; potato 90kcal/2P/20C/0F. Per item: 1 large egg 78kcal/6P/1C/5F; \
    1 slice bread 80kcal/3P/15C/1F; 1 oz cheese 110kcal/7P/1C/9F; 1 tbsp oil/butter 120kcal/0P/0C/14F \
    (count oil ONLY when the food is genuinely fried in it or dressed with it).
    4. Sum the macros for ONE normal serving and SANITY-CHECK against typical ranges: a single meal is \
    usually ~300–800 kcal, 15–45g protein, 20–80g carbs, and 8–30g FAT. Only deep-fried, very oily, or \
    heavily cheesy meals exceed ~35g fat. If your fat or carbs land above these ranges, you over-counted \
    — bring them back down to the realistic amount.
    5. Set calories = round(4×proteinGrams + 4×carbsGrams + 9×fatGrams) so the numbers stay consistent.
    Put a short component breakdown with portions in "notes" (e.g. "150g chicken, 1 cup rice, light oil").
    """

    /// The exact JSON shape we parse. `<int>` (whole grams / whole calories) only.
    static let nutritionSchema =
    "{\"name\":\"<dish name>\",\"calories\":<int>,\"proteinGrams\":<int>,\"carbsGrams\":<int>,\"fatGrams\":<int>,\"confidence\":\"low|medium|high\",\"notes\":\"<components + portions>\"}"

    /// The system instruction shared by every nutrition call.
    static let nutritionSystem = """
    You are a meticulous nutrition estimator. You ALWAYS return a single JSON object \
    with exactly the requested keys — never refuse, never apologize, never wrap it in \
    markdown, never add prose. `calories` MUST equal 4×proteinGrams + 4×carbsGrams + \
    9×fatGrams (whole numbers). If uncertain, set confidence to "low" but still give \
    your best numeric estimate. No emojis. No text outside the JSON.
    """

    // MARK: - Helpers

    /// Clamp to non-negative and enforce on-screen consistency: the calories must
    /// equal 4·protein + 4·carbs + 9·fat. The cheap model frequently returns a
    /// calorie figure that contradicts its own macros (the "way off" complaint);
    /// the macros are component-derived, so we trust them and recompute calories
    /// whenever the two disagree by more than ~12%.
    private func reconcile(_ w: MealEntryWire) -> MealEntryWire {
        let p = max(0, w.proteinGrams)
        let c = max(0, w.carbsGrams)
        let f = max(0, w.fatGrams)
        let kcalFromMacros = 4 * p + 4 * c + 9 * f
        var cal = max(0, w.calories)
        if kcalFromMacros > 0 {
            let drift = abs(Double(cal) - Double(kcalFromMacros)) / Double(kcalFromMacros)
            if cal == 0 || drift > 0.12 { cal = kcalFromMacros }
        }
        return MealEntryWire(name: w.name, calories: cal, proteinGrams: p,
                             carbsGrams: c, fatGrams: f, confidence: w.confidence, notes: w.notes)
    }

    /// A parsed estimate is only usable if it carries at least some nutrition.
    /// Guards against a model that returns an empty `{}` (which would otherwise
    /// log a meaningless 0-calorie entry).
    private func isUsable(_ w: MealEntryWire) -> Bool {
        w.calories > 0 || w.proteinGrams > 0 || w.carbsGrams > 0 || w.fatGrams > 0
    }

    /// Pull the first balanced JSON object out of a response that may contain
    /// markdown fences, leading prose, or trailing text. Falls back to the
    /// trimmed input so JSONDecoder produces a meaningful error if there
    /// genuinely is no JSON.
    private func stripFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```json / ``` fences
        if t.hasPrefix("```json") { t = String(t.dropFirst(7)) }
        else if t.hasPrefix("```") { t = String(t.dropFirst(3)) }
        if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // If there's still wrapping prose, find the FIRST `{` and walk a
        // brace-matcher to its closing `}` — that's the JSON object.
        guard let firstBrace = t.firstIndex(of: "{") else { return t }
        var depth = 0
        var endIndex: String.Index? = nil
        var i = firstBrace
        while i < t.endIndex {
            let ch = t[i]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { endIndex = i; break }
            }
            i = t.index(after: i)
        }
        if let end = endIndex {
            return String(t[firstBrace...end])
        }
        return t
    }
}

// MARK: - Models

struct MealEntry: Identifiable, Codable {
    let id: UUID
    let loggedAt: Date
    var name: String
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var confidence: String   // "low" | "medium" | "high"
    var notes: String
    let source: Source
    /// Filename (in Documents/meal_photos) of the original JPEG, if this was a
    /// photo log. nil for text logs or entries logged before this field existed.
    var photoFilename: String? = nil
    /// The user's most recent free-text correction ("it's actually a chicken
    /// caesar wrap"). Persisted so it survives restarts and is fed into any
    /// future re-analysis.
    var correctionNote: String? = nil

    enum Source: String, Codable { case photo, text }
}

private struct MealEntryWire: Codable {
    let name: String
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let confidence: String
    let notes: String
}
