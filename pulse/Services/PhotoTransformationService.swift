import SwiftUI
import UIKit
import Combine

// MARK: - Inputs to plan generation

enum TrainingStyle: String, CaseIterable, Identifiable, Codable {
    case home = "home"
    case gym = "gym"
    case calisthenics = "calisthenics"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home:         return "Home (no equipment)"
        case .gym:          return "Gym (full equipment)"
        case .calisthenics: return "Calisthenics (bodyweight + bar)"
        }
    }

    var shortName: String {
        switch self {
        case .home:         return "Home"
        case .gym:          return "Gym"
        case .calisthenics: return "Calisthenics"
        }
    }

    var icon: String {
        switch self {
        case .home:         return "house.fill"
        case .gym:          return "dumbbell.fill"
        case .calisthenics: return "figure.gymnastics"
        }
    }

    var equipment: String {
        switch self {
        case .home:         return "Bodyweight only. No dumbbells, no machines, no bar."
        case .gym:          return "Full commercial gym: dumbbells, barbells, machines, cables."
        case .calisthenics: return "Bodyweight + a pull-up bar + optional rings or parallettes."
        }
    }
}

enum WeightUnit: String, CaseIterable, Codable {
    case lb, kg
    var label: String { self.rawValue.uppercased() }
}

// MARK: - Plan result types (structured)

struct DailyMacros: Codable {
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
}

struct WorkoutExercise: Codable, Identifiable {
    var id: String { name + "-\(sets)-\(reps)" }
    let name: String
    let sets: Int
    let reps: String       // e.g. "8-12" or "30 sec"
    let restSeconds: Int
    let notes: String?
}

struct DailyWorkout: Codable, Identifiable {
    var id: String { "\(dayOffset)-\(title)" }
    let dayOffset: Int            // 0 = today, 1 = tomorrow, etc.
    let title: String             // e.g. "Push Day", "Active Recovery"
    let focus: String             // e.g. "Chest, Shoulders, Triceps"
    let estimatedMinutes: Int
    let exercises: [WorkoutExercise]
    let isRestDay: Bool
}

struct TransformationPlan: Identifiable, Codable {
    var id = UUID()
    let assessment: String          // honest current → goal comparison
    let estimatedWeeks: Int
    let currentBodyFatPct: Int
    let goalBodyFatPct: Int
    let dailyMacros: DailyMacros
    let mealsGuidance: String       // free-text — meal timing, key foods, supplements
    let workouts: [DailyWorkout]    // ~one per day for the program
    let weeklyMilestones: [String]
    let habits: [String]
    let trainingStyle: String
    let weight: Double
    let weightUnit: String
    /// True when the plan was hand-built in the no-AI Custom Workout builder.
    /// Optional + defaulted so existing AI-plan JSON still decodes, and the
    /// detail screen knows to hide body-fat / meal / AI-only UI.
    var isManual: Bool? = nil
}

// MARK: - Live duration estimate
//
// One formula so a workout's shown duration reflects the REAL config —
// rounds × work-per-round + rest BETWEEN rounds, summed across exercises —
// and updates live as the user edits, instead of a static `count * 8` guess.
// Mirrors LiveWorkoutView's per-exercise parsing so the estimate matches what
// Live mode actually runs. Derived on read; the stored `estimatedMinutes` JSON
// field is left intact (no Core Data / Codable migration).

private func pulseFirstInt(_ s: String) -> Int? {
    var digits = ""
    for ch in s {
        if ch.isNumber { digits.append(ch) }
        else if !digits.isEmpty { break }
    }
    return Int(digits)
}

extension WorkoutExercise {
    private var secondsPerRep: Int { 3 }   // ~3s per controlled rep
    var roundsEffective: Int { max(1, sets) }
    var isTimedEstimate: Bool {
        let s = reps.lowercased()
        if s.contains("sec") || s.contains("min") { return true }
        let n = name.lowercased()
        return ["plank", "hold", "wall sit", "dead hang", "hollow", "l-sit",
                "l sit", "superman", "isometric", "bridge hold"].contains { n.contains($0) }
    }
    /// Seconds of WORK for one round (a hold's seconds, or reps × secPerRep).
    var workSecondsPerRound: Int {
        let s = reps.lowercased()
        if s.contains("sec") { return pulseFirstInt(s) ?? 30 }
        if s.contains("min") { return (pulseFirstInt(s) ?? 1) * 60 }
        if isTimedEstimate { return 30 }
        let target = (s.contains("max") || s.contains("failure") || s.contains("amrap"))
            ? 12 : (pulseFirstInt(s) ?? 10)
        return target * secondsPerRep
    }
    /// Total seconds for this exercise = rounds × work + rest between rounds.
    var estimatedSeconds: Int {
        let r = roundsEffective
        return r * workSecondsPerRound + max(0, r - 1) * max(0, restSeconds)
    }
}

/// Minutes for a set of exercises (work + between-round rest + a small
/// inter-exercise transition buffer), rounded up. Shared by the live header
/// and every persistence write site so they always agree.
func pulseWorkoutMinutes(_ exercises: [WorkoutExercise]) -> Int {
    let secs = exercises.reduce(0) { $0 + $1.estimatedSeconds }
    let withBuffer = secs + max(0, exercises.count - 1) * 20
    return max(1, Int((Double(withBuffer) / 60.0).rounded(.up)))
}

extension DailyWorkout {
    /// Live duration in minutes derived from the real config (0 on a rest day).
    var computedMinutes: Int { isRestDay ? 0 : pulseWorkoutMinutes(exercises) }
}

// MARK: - Service

@MainActor
class PhotoTransformationService: ObservableObject {
    static let shared = PhotoTransformationService()

    @Published var isAnalyzing = false
    @Published var analysisResult: TransformationPlan?
    @Published var currentPhotoData: Data?
    @Published var goalPhotoData: Data?
    @Published var error: String?

    /// Generate a personalized workout + meal plan from photos + inputs.
    /// `targetWeeks` is the user's chosen commitment. AI plans within that window.
    /// Body-fat is estimated by the vision model from the photos — the user
    /// never types it. `customInstructions` carry any freeform guidance the user
    /// added in the Edit screen (and an optional body-fat correction line).
    func generatePlan(
        currentPhoto: UIImage,
        goalPhoto: UIImage,
        trainingStyle: TrainingStyle,
        weight: Double,
        weightUnit: WeightUnit,
        targetWeeks: Int,
        customInstructions: String? = nil
    ) async {
        isAnalyzing = true
        error = nil
        analysisResult = nil

        guard let currentData = currentPhoto.jpegData(compressionQuality: 0.6),
              let goalData = goalPhoto.jpegData(compressionQuality: 0.6) else {
            error = "Failed to process images"
            isAnalyzing = false
            return
        }
        currentPhotoData = currentData
        goalPhotoData = goalData

        let prompt = buildPrompt(trainingStyle: trainingStyle, weight: weight, unit: weightUnit,
                                 targetWeeks: targetWeeks,
                                 customInstructions: customInstructions)
        let systemPrompt = """
        You are an elite fitness coach and body transformation specialist with 20 years of experience.
        You design realistic, periodized programs. You never recommend dangerous calorie restriction
        (minimum 1500 kcal/day for adults). You always cite specific exercises, sets, and reps.
        You write detailed, actionable instructions a beginner could follow. Return ONLY valid JSON
        matching the schema exactly. No markdown fences, no prose outside the JSON.
        """

        do {
            // Gemini analyzes the user's ACTUAL photos: the first ("current") shot
            // is the before-physique it assesses for body composition; the second
            // ("goal") shot is the look they're aiming for. The vision client
            // downscales each image to ≤768px before upload, so the payload stays
            // well under the proxy's size cap. (DeepSeek was text-only and 400'd on
            // images; Gemini sees them, so the plan is personalized again.)
            let raw = try await GeminiAPIService.shared.sendVisionMessage(
                textPrompt: prompt,
                images: [
                    (data: currentData, mimeType: "image/jpeg"),
                    (data: goalData, mimeType: "image/jpeg")
                ],
                systemPrompt: systemPrompt,
                temperature: 0.4,
                maxTokens: 8000
            )

            let cleaned = extractFirstJSONObject(raw)
            guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else {
                #if DEBUG
                print("[Transformation] AI returned no parseable JSON. Raw response:\n\(raw.prefix(2000))")
                #endif
                throw NSError(domain: "Transformation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The AI couldn't generate a plan from these photos. Try clearer, well-lit, full-body photos and tap Create Plan again."])
            }
            let decoder = JSONDecoder()
            do {
                let plan = try decoder.decode(TransformationPlanWire.self, from: data)

                analysisResult = TransformationPlan(
                    assessment: plan.assessment,
                    estimatedWeeks: plan.estimatedWeeks,
                    currentBodyFatPct: plan.currentBodyFatPct,
                    goalBodyFatPct: plan.goalBodyFatPct,
                    dailyMacros: plan.dailyMacros,
                    mealsGuidance: plan.mealsGuidance,
                    workouts: plan.workouts,
                    weeklyMilestones: plan.weeklyMilestones,
                    habits: plan.habits,
                    trainingStyle: trainingStyle.rawValue,
                    weight: weight,
                    weightUnit: weightUnit.rawValue
                )
            } catch {
                #if DEBUG
                print("[Transformation] JSON decode failed: \(error)")
                print("[Transformation] Cleaned payload (first 2000 chars):\n\(cleaned.prefix(2000))")
                #endif
                throw NSError(domain: "Transformation", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "The AI's plan was incomplete. Tap Create Plan again — usually works on retry."])
            }
            // Clear photo data from memory immediately after AI returns —
            // no reason to keep potentially sensitive images in @Published state.
            currentPhotoData = nil
            goalPhotoData = nil
            isAnalyzing = false
        } catch {
            currentPhotoData = nil
            goalPhotoData = nil
            self.error = error.localizedDescription
            isAnalyzing = false
        }
    }

    /// One-off chat to answer a user's question about THEIR transformation plan.
    func askAboutPlan(question: String, plan: TransformationPlan) async throws -> String {
        let context = """
        USER'S TRANSFORMATION PLAN:
        Training style: \(plan.trainingStyle)
        Weight: \(plan.weight) \(plan.weightUnit)
        Daily macros: \(plan.dailyMacros.calories) kcal · \(plan.dailyMacros.proteinGrams)g protein · \(plan.dailyMacros.carbsGrams)g carbs · \(plan.dailyMacros.fatGrams)g fat
        Estimated weeks: \(plan.estimatedWeeks)
        Assessment: \(plan.assessment)
        """
        let system = """
        You are the user's personal fitness and nutrition coach. Answer their question
        clearly using THEIR plan above. Stay short — 2-4 sentences unless they ask for
        depth. Cite real numbers from the plan when relevant. No emojis.
        """ + LocalizationManager.shared.aiLanguageInstruction

        return try await AIRouter.shared.sendMessage(
            userMessage: "\(context)\n\nUSER QUESTION: \(question)",
            systemPrompt: system,
            temperature: 0.6,
            maxTokens: 600
        )
    }

    /// Live-AI exercise swaps. The user taps "Swap" on an exercise and the AI
    /// returns real alternatives that hit the same muscles within their
    /// equipment. Replaces the old prebaked WorkoutLibrary lookup — 100% AI.
    func alternativeExercises(
        for exerciseName: String,
        trainingStyle: String,
        originalSets: Int,
        count: Int = 8
    ) async throws -> [WorkoutExercise] {
        let style = TrainingStyle(rawValue: trainingStyle) ?? .home
        let sets = max(1, originalSets)
        let prompt = """
        The user is mid-workout and wants to SWAP OUT this exercise:
        "\(exerciseName)"

        Suggest \(count) alternative exercises that:
        - Train the SAME primary muscle group(s) as "\(exerciseName)".
        - Are doable with EXACTLY this equipment: \(style.equipment)
          Never suggest gear the user doesn't have.
        - Use real, well-known movements with standard, searchable names a
          beginner can look up on YouTube.
        - Range from easier to harder so the user has genuine choice.

        Return ONLY this JSON, nothing else:
        {
          "alternatives": [
            {
              "name": "<exercise name>",
              "sets": \(sets),
              "reps": "<single integer like \\"10\\" OR a timed hold like \\"30 sec\\">",
              "restSeconds": <rest between sets in seconds, e.g. 60>,
              "notes": "<short form cue, under 60 chars, no set/round counts>"
            }
          ]
        }

        RULES:
        - sets must always be \(sets).
        - reps is a single integer (e.g. "10") or a timed hold (e.g. "30 sec"). Never hyphen ranges.
        - Keep notes short — form cue only, no round/set counts.
        - START YOUR RESPONSE WITH `{` AND END WITH `}`.
        """
        let system = """
        You are an elite strength coach who knows thousands of exercises and
        their muscle targets. You only prescribe movements that match the user's
        available equipment. Return ONLY valid JSON matching the schema. No
        markdown fences, no prose outside the JSON.
        """

        let raw = try await AIRouter.shared.sendMessageJSON(
            userMessage: prompt,
            systemPrompt: system,
            temperature: 0.5,
            maxTokens: 1500
        )
        let cleaned = extractFirstJSONObject(raw)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "Transformation", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't load alternatives. Tap Swap again."])
        }
        let decoded = try JSONDecoder().decode(AlternativesWire.self, from: data)
        return decoded.alternatives
    }

    // MARK: - Helpers

    private func buildPrompt(
        trainingStyle: TrainingStyle,
        weight: Double,
        unit: WeightUnit,
        targetWeeks: Int,
        customInstructions: String? = nil
    ) -> String {
        // Freeform guidance the user typed in the Edit screen (and/or a
        // body-fat correction line). These are user PREFERENCES layered on top
        // of the photo analysis — the AI still estimates body fat from the
        // images, but honors any explicit correction the user gives here.
        let customBlock: String
        if let c = customInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            customBlock = """
            USER INSTRUCTIONS — follow these closely, they override defaults where they conflict:
            \(c)
            """
        } else {
            customBlock = ""
        }
        return """
        Build a personalized body-transformation plan. You are given TWO photos: the
        FIRST is the user's CURRENT physique (assess it); the SECOND is the user's
        GOAL physique (what they're aiming for). Combine what you see in the photos
        with the user's stats below.

        USER INPUTS:
        - Training style: \(trainingStyle.displayName)
        - Equipment available: \(trainingStyle.equipment)
        - Current weight: \(Int(weight)) \(unit.label)
        - USER-CHOSEN COMMITMENT: \(targetWeeks) weeks. Use exactly this for estimatedWeeks.
          Even if the goal seems ambitious in this window, build the best possible plan
          for \(targetWeeks) weeks and be honest in the assessment about what's actually
          achievable. NEVER override the user's chosen duration.

        \(customBlock)

        BODY FAT %: Assess the user's current body-fat percentage from the FIRST
        (current) photo — judge visible muscle definition, the midsection, and
        overall composition. Set currentBodyFatPct to your visual estimate. Set
        goalBodyFatPct to a sensible, achievable target for the chosen
        \(targetWeeks)-week window (a realistic reduction, not a dramatic one),
        informed by the goal photo. If a photo is unclear, not full-body, or clothed
        in a way that hides composition, say so in the assessment and give a
        conservative estimate rather than overclaiming.

        Create a complete, realistic, daily transformation plan. Output JSON ONLY,
        matching this schema EXACTLY (no markdown fences):

        {
          "assessment": "<2-3 honest sentences on the plan and what's realistically achievable in \(targetWeeks) weeks, grounded in what you actually see in the current photo. Avoid generic praise.>",
          "estimatedWeeks": \(targetWeeks),
          "currentBodyFatPct": <integer 8-35>,
          "goalBodyFatPct": <integer 6-25>,
          "dailyMacros": {
            "calories": <integer>,
            "proteinGrams": <integer>,
            "carbsGrams": <integer>,
            "fatGrams": <integer>
          },
          "mealsGuidance": "<3-5 sentence guidance: meal timing, key foods, hydration. Include suggested protein sources for their style.>",
          "workouts": [
            {
              "dayOffset": 0,
              "title": "<e.g. Push Day or Active Recovery>",
              "focus": "<e.g. Chest, Shoulders, Triceps>",
              "estimatedMinutes": <integer>,
              "isRestDay": false,
              "exercises": [
                { "name": "<exercise>", "sets": 3, "reps": "<SINGLE number like 10 or 12, OR a timed hold like 30 sec — NEVER a range like 8-12>", "restSeconds": <int>, "notes": "<form cue or null>" }
              ]
            }
          ],
          "weeklyMilestones": ["<week 2 marker>", "<week 4 marker>", "<week 8 marker>"],
          "habits": ["<habit 1>", "<habit 2>", "<habit 3>"]
        }

        REQUIREMENTS:
        - Generate workouts for EXACTLY 7 days (dayOffset 0-6). Include rest days where appropriate.
        - HARD EQUIPMENT CONSTRAINT: \(equipmentConstraint(for: trainingStyle))
          Every exercise you prescribe MUST be doable with exactly this
          equipment — never suggest gear the user doesn't have.
        - Choose the most effective exercises for each day yourself. Use real,
          well-known movements with standard, searchable names a beginner can
          look up. Distribute coverage across muscle groups across the week
          (push day, pull day, leg day, full-body, recovery, etc. as appropriate).
        - Calorie target must be safe (1500+ for adults). Calculate from weight (\(Int(weight)) \(unit.label)) with reasonable deficit/surplus.
        - Protein must be at least 1.6g per kg (or 0.73g per lb).
        - REPS must always be a single integer (e.g. "10") or a timed hold (e.g. "30 sec"). Never hyphen ranges.
        - SETS must always be 3 — the app runs 3 rounds of each exercise itself.
          NEVER write "repeat 3 rounds", "3 rounds", "x3", or round counts in
          the notes or anywhere else — the app handles rounds automatically.
        - For plank / wall sit / hollow hold and other holds, reps is a time
          like "30 sec" (default 30s), NOT a number.
        - Keep notes short (under 60 chars) — form cue only, no round/set counts.
        - Be honest if the goal is unrealistic. Don't sugarcoat.
        - START YOUR RESPONSE WITH `{` AND END WITH `}`. No prose before or after.
        """
    }

    /// The hard equipment rule for the user's chosen training style. Injected
    /// into the prompt so the AI never suggests gear the user doesn't have.
    private func equipmentConstraint(for style: TrainingStyle) -> String {
        style.equipment
    }

    /// Pull the first balanced JSON object out of a response that may have
    /// markdown fences, leading prose, or trailing chatter.
    private func extractFirstJSONObject(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)

        if t.hasPrefix("```json") { t = String(t.dropFirst(7)) }
        else if t.hasPrefix("```") { t = String(t.dropFirst(3)) }
        if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the first `{` and brace-walk to its matching `}`.
        guard let firstBrace = t.firstIndex(of: "{") else { return "" }
        var depth = 0
        var inString = false
        var escape = false
        var endIndex: String.Index? = nil
        var i = firstBrace
        while i < t.endIndex {
            let ch = t[i]
            if escape { escape = false }
            else if ch == "\\" && inString { escape = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { endIndex = i; break }
                }
            }
            i = t.index(after: i)
        }
        if let end = endIndex {
            return String(t[firstBrace...end])
        }
        // Truncated JSON — give the decoder a chance anyway.
        return String(t[firstBrace...])
    }
}

/// Wire-format for the live-AI exercise-swap response. `WorkoutExercise` is
/// already Codable (its `id` is computed, so it decodes straight from these
/// fields), so we just wrap the array.
private struct AlternativesWire: Codable {
    let alternatives: [WorkoutExercise]
}

/// Wire-format intermediate (no UUID id) so Codable parses cleanly.
private struct TransformationPlanWire: Codable {
    let assessment: String
    let estimatedWeeks: Int
    let currentBodyFatPct: Int
    let goalBodyFatPct: Int
    let dailyMacros: DailyMacros
    let mealsGuidance: String
    let workouts: [DailyWorkout]
    let weeklyMilestones: [String]
    let habits: [String]
}
