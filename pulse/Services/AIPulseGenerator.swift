import Foundation
import CoreData
import WidgetKit

/// Generates pulses (DailyTask entities) for a Goal by asking the AI to build
/// an idiot-proof roadmap. The formula:
///
///   • motivation 1–10  → success-probability multiplier (higher = more aggressive plan)
///   • timePerDay (min) → per-pulse depth (more time = bigger pulses, fewer per day)
///   • deadline (days)  → roadmap length
///   • skillLevel       → starting difficulty
///
/// More motivation × more time × longer deadline = more pulses + higher probability.
final class AIPulseGenerator {
    static let shared = AIPulseGenerator()
    private init() {}

    /// Generate pulses for an existing Goal and save them to Core Data.
    func generatePulses(forGoalWithID objectID: NSManagedObjectID) async {
        let ctx = PersistenceController.shared.newBackgroundContext()
        await ctx.perform {
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return }
            let snapshot = GoalSnapshot(from: goal)

            Task {
                do {
                    let plan = try await self.requestRoadmap(snapshot: snapshot)
                    await self.savePulses(plan: plan, forGoalWithID: objectID)
                } catch {
                    #if DEBUG
                    print("[AIPulseGenerator] roadmap failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    /// FOREGROUND-blocking AI roadmap generation. Used by dedicated goal
    /// creation views (Make Money / Master a Skill / Big Project / Anything
    /// Else) so the user waits on a "Building your AI roadmap…" overlay until
    /// REAL personalized pulses land.
    ///
    /// Returns the AI's pulse count on success, or 0 on failure. The
    /// `lastError` property carries the human-readable error string so the
    /// failure dialog can show it instead of just "AI is having trouble".
    ///
    /// Writes pulses on the MAIN viewContext so any view already observing
    /// the goal refreshes immediately on return.
    var lastError: String? = nil

    @discardableResult
    func generatePulsesAndWait(forGoalWithID objectID: NSManagedObjectID, requestedCount: Int = 20, extraInstructions: String? = nil) async -> Bool {
        lastError = nil
        // AI is free for everyone, so `hasAIGeneration` is always true. This guard
        // is a defensive fallback for the (currently unreachable) case where AI is
        // unavailable; Pro only adds unlimited goals + Primary Access (priority AI).
        let hasAI = await MainActor.run { SubscriptionManager.shared.hasAIGeneration }
        guard hasAI else {
            lastError = "AI is temporarily unavailable. Please try again."
            return false
        }
        // Snapshot off the main thread (read-only).
        let snapshot = await MainActor.run { () -> GoalSnapshot? in
            let ctx = PersistenceController.shared.container.viewContext
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return nil }
            return GoalSnapshot(from: goal)
        }
        guard let snap = snapshot else {
            lastError = "Goal not found"
            return false
        }

        let target = max(1, min(requestedCount, 200))
        let batchSize = 14
        var all: [AIRoadmapPlan.Pulse] = []
        var probability = 0
        var fastestPath = ""

        // FIRST batch — carries probability + fastestPath. Hard 180s timeout
        // (matches the URLSession request timeout; 60s was cutting off slow but
        // valid generations, surfacing as "AI took too long").
        do {
            let firstCount = min(target, batchSize)
            let plan = try await withTimeout(seconds: 180) {
                try await self.requestRoadmap(snapshot: snap, count: firstCount, extraInstructions: extraInstructions)
            }
            all = plan.pulses
            probability = plan.probabilityScore
            fastestPath = plan.fastestPath
        } catch is CancellationError {
            lastError = "The AI is taking longer than usual — tap Try again (plans can take up to 3 minutes)."
            #if DEBUG
            print("[AIPulseGenerator] timeout after 180s")
            #endif
            return false
        } catch {
            lastError = error.localizedDescription
            #if DEBUG
            print("[AIPulseGenerator] generatePulsesAndWait failed: \(error.localizedDescription)")
            #endif
            return false
        }

        guard !all.isEmpty else {
            lastError = "AI returned 0 pulses — usually a transient issue"
            #if DEBUG
            print("[AIPulseGenerator] AI returned 0 pulses")
            #endif
            return false
        }

        // REMAINING batches via the extension prompt so we don't repeat what's
        // already generated. Best-effort: if a later batch fails we keep every
        // pulse we already have (all real AI) and stop extending.
        while all.count < target {
            let need = min(batchSize, target - all.count)
            do {
                let ext = try await withTimeout(seconds: 45) {
                    try await self.requestExtensionPulses(
                        snapshot: snap,
                        completedTitles: all.map { $0.title },
                        howMany: need
                    )
                }
                if ext.pulses.isEmpty { break }
                all += ext.pulses
            } catch {
                #if DEBUG
                print("[AIPulseGenerator] extension batch failed, keeping \(all.count): \(error.localizedDescription)")
                #endif
                break
            }
        }
        if all.count > target { all = Array(all.prefix(target)) }
        #if DEBUG
        print("[AIPulseGenerator] AI returned \(all.count) pulses (target \(target))")
        #endif

        let plan = AIRoadmapPlan(probabilityScore: probability, fastestPath: fastestPath,
                                 skillGaps: [], requiredHabits: [], pulses: all)

        // Write on viewContext so the UI refreshes immediately when we return.
        await MainActor.run {
            let ctx = PersistenceController.shared.container.viewContext
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return }

            // Mark as AI-built so it locks if the user downgrades to Free.
            ProGoalRegistry.mark(goal.id?.uuidString)

            goal.aiProbabilityScore = Float(plan.probabilityScore)
            goal.fastestPathSummary = plan.fastestPath

            // Replace any existing (e.g. previous-attempt) pulses with the AI's.
            if let existing = goal.dailyTasks as? Set<DailyTask>, !existing.isEmpty {
                existing.forEach { ctx.delete($0) }
            }

            for (i, p) in plan.pulses.enumerated() {
                let task = DailyTask(context: ctx)
                task.id = UUID()
                task.title = p.title
                task.taskDescription = p.howTo
                task.howToDescription = p.howTo
                task.proofType = p.proofType
                task.proofDescription = p.proofRequired
                task.stepNumber = Int16(clamping: p.stepNumber == 0 ? i + 1 : p.stepNumber)
                task.sortOrder = Int16(clamping: i)
                task.estimatedMinutes = Int16(clamping: p.estimatedMinutes)
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: p.scheduledDayOffset, to: Date())
                task.xpReward = 10
                task.verificationStatus = "pending"
                task.isCompleted = false
                task.goal = goal
            }

            try? ctx.save()
            WidgetDataService.shared.updateWidgets(context: ctx)
        }

        // Background Firestore sync.
        Task.detached(priority: .utility) {
            await MainActor.run {
                let ctx = PersistenceController.shared.container.viewContext
                if let goal = try? ctx.existingObject(with: objectID) as? Goal {
                    Task.detached { try? await FirestoreSyncService.shared.syncGoal(goal) }
                }
            }
        }

        return true
    }

    /// APPEND additional pulses to an existing goal. Used by the "Generate
    /// More Pulses" button on every goal detail page — for users who finished
    /// their plan and want to keep going, or who feel their plan is too short.
    ///
    /// AI-ONLY: AI is free for everyone. Returns 0 on a missing goal, when AI is
    /// unavailable, or when the AI fails / returns nothing. There is NO precoded
    /// template fallback — if
    /// the AI can't generate, we create nothing and the button surfaces the real
    /// error (e.g. "Usage limit hit") so the user can retry.
    ///
    /// Writes on the MAIN viewContext so existing `@ObservedObject var goal`
    /// bindings (in TransformationDetailView, GoalDetailView, etc.) refresh
    /// immediately. Saving to a background context here was the original bug —
    /// the change merged into viewContext asynchronously and views appeared
    /// not to update, making it look like nothing happened.
    @discardableResult
    func appendMorePulses(
        forGoalWithID objectID: NSManagedObjectID,
        howMany: Int = 7
    ) async -> Int {
        // AI is free for everyone (hasAIGeneration is always true); this guard is a
        // defensive fallback for when AI is unavailable.
        let hasAI = await MainActor.run { SubscriptionManager.shared.hasAIGeneration }
        guard hasAI else { return 0 }
        // Step 1: Snapshot what we need OFF the main thread (read-only).
        let snapshotData = await MainActor.run { () -> (snapshot: GoalSnapshot, completed: [String])? in
            let ctx = PersistenceController.shared.container.viewContext
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return nil }
            let snapshot = GoalSnapshot(from: goal)
            let completed = (goal.dailyTasks as? Set<DailyTask> ?? [])
                .filter { $0.isCompleted }
                .compactMap { $0.title }
            return (snapshot, completed)
        }
        guard let data = snapshotData else { return 0 }

        // Step 2: Try the AI. Best-effort with a hard 25s timeout so the user
        // isn't waiting forever if Groq is slow.
        var aiPulses: [AIRoadmapPlan.Pulse] = []
        do {
            let plan = try await withTimeout(seconds: 25) {
                try await self.requestExtensionPulses(
                    snapshot: data.snapshot,
                    completedTitles: data.completed,
                    howMany: howMany
                )
            }
            // Accept ANY non-empty AI response — even 1 pulse is real personalization,
            // better than recycling a hand-crafted template.
            aiPulses = plan.pulses
            #if DEBUG
            print("[AIPulseGenerator] appendMorePulses AI returned \(plan.pulses.count) pulses")
            #endif
        } catch {
            #if DEBUG
            print("[AIPulseGenerator] appendMorePulses AI failed: \(error.localizedDescription)")
            #endif
        }

        // Step 3: Only write if the AI actually returned something. NO silent
        // template fallback — the user explicitly complained that "AI isn't
        // generating, you're just reusing templates from other goals." If AI
        // fails we return 0 and the button surfaces the real error so the
        // user can retry instead of being lied to with a template.
        guard !aiPulses.isEmpty else { return 0 }

        let addedCount = await MainActor.run { () -> Int in
            let ctx = PersistenceController.shared.container.viewContext
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return 0 }
            let existing = (goal.dailyTasks as? Set<DailyTask> ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            let maxStep = existing.map { Int($0.stepNumber) }.max() ?? 0
            let existingCount = existing.count
            let baseDate = existing.compactMap { $0.scheduledDate }.max() ?? Date()
            let startDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? Date()

            for (i, p) in aiPulses.enumerated() {
                let task = DailyTask(context: ctx)
                task.id = UUID()
                task.title = p.title
                task.taskDescription = p.howTo
                task.howToDescription = p.howTo
                task.proofType = p.proofType
                task.proofDescription = p.proofRequired
                task.stepNumber = Int16(clamping: maxStep + 1 + i)
                task.sortOrder = Int16(clamping: existingCount + i)
                task.estimatedMinutes = Int16(clamping: p.estimatedMinutes)
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: i, to: startDate)
                task.xpReward = 10
                task.verificationStatus = "pending"
                task.isCompleted = false
                task.goal = goal
            }

            do {
                try ctx.save()
            } catch {
                #if DEBUG
                print("[AIPulseGenerator] appendMorePulses save failed: \(error)")
                #endif
            }

            WidgetDataService.shared.updateWidgets(context: ctx)
            return aiPulses.count
        }

        // Step 4: Fire-and-forget Firestore sync of the goal (incl. new pulses).
        Task.detached(priority: .utility) {
            await MainActor.run {
                let ctx = PersistenceController.shared.container.viewContext
                if let goal = try? ctx.existingObject(with: objectID) as? Goal {
                    Task.detached { try? await FirestoreSyncService.shared.syncGoal(goal) }
                }
            }
        }

        return addedCount
    }

    /// REGENERATE the unfinished portion of a plan, keeping every COMPLETED
    /// pulse intact. This is the mentor agent's "start from where I'm holding"
    /// power — the user finished N pulses, doesn't like the rest, and asks the
    /// mentor to rebuild the remainder (optionally with custom instructions).
    ///
    /// Completed pulses stay; all incomplete pulses are deleted and replaced
    /// with a fresh AI-built continuation that does NOT repeat finished work.
    /// Returns the number of new pulses written, or 0 on Free / failure.
    @discardableResult
    func regenerateRemaining(
        forGoalWithID objectID: NSManagedObjectID,
        requestedCount: Int = 12,
        extraInstructions: String? = nil
    ) async -> Int {
        lastError = nil
        // AI is free for everyone; this guard only trips if AI is unavailable.
        let hasAI = await MainActor.run { SubscriptionManager.shared.hasAIGeneration }
        guard hasAI else { lastError = "AI is temporarily unavailable. Please try again."; return 0 }

        // Snapshot goal + completed titles (read-only, main).
        let prep = await MainActor.run { () -> (snap: GoalSnapshot, completed: [String], keepCount: Int, maxStep: Int, baseDate: Date)? in
            let ctx = PersistenceController.shared.container.viewContext
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return nil }
            let all = (goal.dailyTasks as? Set<DailyTask> ?? [])
            let done = all.filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
            let completedTitles = done.compactMap { $0.title }
            let maxStep = done.map { Int($0.stepNumber) }.max() ?? 0
            let baseDate = done.compactMap { $0.scheduledDate }.max() ?? Date()
            return (GoalSnapshot(from: goal), completedTitles, done.count, maxStep, baseDate)
        }
        guard let prep else { lastError = "Goal not found"; return 0 }

        // Ask the AI to continue the plan, never repeating finished pulses.
        let combinedInstructions = """
        The user has ALREADY COMPLETED these pulses — do NOT repeat them, build on them:
        \(prep.completed.isEmpty ? "(none yet)" : prep.completed.map { "- \($0)" }.joined(separator: "\n"))

        \(extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "USER'S INSTRUCTIONS FOR THE REMAINDER (follow above all else):\n\(extraInstructions!)" : "Rebuild the remaining roadmap to be more effective and continue from where they are.")
        """

        var plan: AIRoadmapPlan
        do {
            plan = try await withTimeout(seconds: 180) {
                try await self.requestRoadmap(snapshot: prep.snap, count: max(1, min(requestedCount, 14)), extraInstructions: combinedInstructions)
            }
        } catch is CancellationError {
            lastError = "The AI is taking longer than usual — tap Try again (plans can take up to 3 minutes)."; return 0
        } catch {
            lastError = error.localizedDescription; return 0
        }
        guard !plan.pulses.isEmpty else { lastError = "AI returned 0 pulses"; return 0 }

        // Delete incomplete pulses, append the AI continuation after completed.
        let added = await MainActor.run { () -> Int in
            let ctx = PersistenceController.shared.container.viewContext
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return 0 }
            ProGoalRegistry.mark(goal.id?.uuidString)
            if let existing = goal.dailyTasks as? Set<DailyTask> {
                existing.filter { !$0.isCompleted }.forEach { ctx.delete($0) }
            }
            if plan.probabilityScore > 0 { goal.aiProbabilityScore = Float(plan.probabilityScore) }
            if !plan.fastestPath.isEmpty { goal.fastestPathSummary = plan.fastestPath }
            let startDate = Calendar.current.date(byAdding: .day, value: 1, to: prep.baseDate) ?? Date()
            for (i, p) in plan.pulses.enumerated() {
                let task = DailyTask(context: ctx)
                task.id = UUID()
                task.title = p.title
                task.taskDescription = p.howTo
                task.howToDescription = p.howTo
                task.proofType = p.proofType
                task.proofDescription = p.proofRequired
                task.stepNumber = Int16(clamping: prep.maxStep + 1 + i)
                task.sortOrder = Int16(clamping: prep.keepCount + i)
                task.estimatedMinutes = Int16(clamping: p.estimatedMinutes)
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: i, to: startDate)
                task.xpReward = 10
                task.verificationStatus = "pending"
                task.isCompleted = false
                task.goal = goal
            }
            try? ctx.save()
            WidgetDataService.shared.updateWidgets(context: ctx)
            return plan.pulses.count
        }

        Task.detached(priority: .utility) {
            await MainActor.run {
                let ctx = PersistenceController.shared.container.viewContext
                if let goal = try? ctx.existingObject(with: objectID) as? Goal {
                    Task.detached { try? await FirestoreSyncService.shared.syncGoal(goal) }
                }
            }
        }
        return added
    }

    /// Run an async operation with a hard timeout. Throws CancellationError
    /// if the operation doesn't complete in time.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// AI call for the "more pulses" extension — different prompt that
    /// references what's already done so we don't repeat exercises.
    private func requestExtensionPulses(
        snapshot: GoalSnapshot,
        completedTitles: [String],
        howMany: Int
    ) async throws -> AIRoadmapPlan {
        let doneList = completedTitles.isEmpty
            ? "(none yet)"
            : completedTitles.prefix(20).map { "• \($0)" }.joined(separator: "\n")

        let languageInstruction = LocalizationManager.shared.aiLanguageInstruction
        let systemPrompt = """
        You are Pulse, an expert goal-achievement coach.
        The user already has a plan in motion. They are asking for MORE pulses
        that pick up where they left off — same depth, same howTo quality.
        Every "howTo" must read like a recipe with numbered steps, quantities,
        tools, common mistakes, and a "you're done when..." line.
        Never repeat what they've already done. Build forward.
        Never use emojis. Return only valid JSON.\(languageInstruction.isEmpty ? "" : "\n" + languageInstruction)
        """

        let userPrompt = """
        Generate EXACTLY \(howMany) ADDITIONAL pulses for this goal. Build on
        what's already been completed. Don't repeat the same exercises or
        actions. Progress the difficulty / depth.

        GOAL: \(snapshot.title)
        CATEGORY: \(snapshot.category)
        SKILL LEVEL: \(snapshot.skillLevel)
        TIME PER DAY: \(snapshot.timePerDay) minutes

        ALREADY COMPLETED:
        \(doneList)

        Return JSON in this exact shape:
        {
          "pulses": [
            {
              "stepNumber": 1,
              "title": "...",
              "howTo": "1. ...\\n2. ...\\n3. ...",
              "proofRequired": "...",
              "proofType": "text",
              "estimatedMinutes": 20,
              "scheduledDayOffset": 0
            }
          ]
        }

        The scheduledDayOffset is days from today (0 = today, 1 = tomorrow…).
        Spread the \(howMany) new pulses across the next \(howMany) days.
        """

        let raw = try await AIRouter.shared.sendMessageJSON(
            userMessage: userPrompt,
            systemPrompt: systemPrompt,
            temperature: 0.6,
            maxTokens: 6000
        )

        let cleaned = Self.extractFirstJSONObject(raw)
        guard !cleaned.isEmpty,
              let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AIPulseGenerator", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "AI returned invalid JSON"])
        }

        let pulses = (json["pulses"] as? [[String: Any]] ?? []).compactMap { dict -> AIRoadmapPlan.Pulse? in
            guard let title = dict["title"] as? String else { return nil }
            return AIRoadmapPlan.Pulse(
                stepNumber: dict["stepNumber"] as? Int ?? 0,
                title: title,
                howTo: dict["howTo"] as? String ?? "",
                proofRequired: dict["proofRequired"] as? String ?? "Describe what you did.",
                proofType: dict["proofType"] as? String ?? "text",
                estimatedMinutes: dict["estimatedMinutes"] as? Int ?? snapshot.timePerDay,
                scheduledDayOffset: dict["scheduledDayOffset"] as? Int ?? 0
            )
        }

        return AIRoadmapPlan(
            probabilityScore: 0,
            fastestPath: "",
            skillGaps: [],
            requiredHabits: [],
            pulses: pulses
        )
    }

    // (legacy background-context append helper removed — the bulletproof
    // appendMorePulses above writes directly on viewContext so UI refreshes
    // immediately and AI is purely best-effort.)

    // MARK: - Probability + step-count formula

    /// LEGACY — kept for the wizard's UI estimate. The AI ultimately decides.
    /// Returns a single number suitable for "you'll get roughly N pulses" hints.
    static func recommendedPulseCount(
        motivation: Int,
        timePerDayMinutes: Int,
        daysUntilDeadline: Int
    ) -> Int {
        let range = suggestedPulseRange(
            motivation: motivation,
            timePerDayMinutes: timePerDayMinutes,
            daysUntilDeadline: daysUntilDeadline
        )
        // Keep the recommendation within the slider's own bounds (5...150) so it
        // never suggests a value the user can't actually pick.
        return min(150, max(5, (range.lowerBound + range.upperBound) / 2))
    }

    /// Suggested RANGE of pulses for this goal. We pass the range to the AI as a
    /// hint, but the AI is free to choose any count that genuinely fits the goal.
    static func suggestedPulseRange(
        motivation: Int,
        timePerDayMinutes: Int,
        daysUntilDeadline: Int
    ) -> ClosedRange<Int> {
        let motivationFactor = max(1, motivation)
        let timeFactor       = max(1, timePerDayMinutes / 15)
        let dayFactor        = max(1, daysUntilDeadline)
        let pulsesPerDay     = max(1, min(timeFactor, motivationFactor / 2 + 1))
        let target = dayFactor * pulsesPerDay
        // High = 140% of target, clamped to [6, 200]. Low = 60% of target but
        // never above high. Guarantees lowerBound <= upperBound so the
        // ClosedRange can never trap ("Range requires lowerBound <= upperBound").
        let high = min(200, max(6, target * 140 / 100))
        let low  = min(high, max(6, target * 60 / 100))
        return low...high
    }

    /// Compute probability of success (0-100) based on inputs.
    /// Higher motivation × more time × reasonable deadline = higher probability.
    static func computeProbability(
        motivation: Int,
        timePerDayMinutes: Int,
        daysUntilDeadline: Int,
        skill: String
    ) -> Int {
        let motivationContrib  = motivation * 6                    // up to 60
        let timeContrib        = min(timePerDayMinutes / 4, 25)    // up to 25
        let deadlineContrib    = min(daysUntilDeadline / 4, 10)    // up to 10
        let skillContrib: Int
        switch skill.lowercased() {
        case "expert":       skillContrib = 5
        case "advanced":     skillContrib = 4
        case "intermediate": skillContrib = 2
        default:             skillContrib = 0
        }
        return min(98, max(15, motivationContrib + timeContrib + deadlineContrib + skillContrib))
    }

    // MARK: - AI call

    private func requestRoadmap(snapshot: GoalSnapshot, count: Int = 12, extraInstructions: String? = nil) async throws -> AIRoadmapPlan {
        let probability = Self.computeProbability(
            motivation: snapshot.motivation,
            timePerDayMinutes: snapshot.timePerDay,
            daysUntilDeadline: snapshot.daysUntilDeadline,
            skill: snapshot.skillLevel
        )

        // CAP per-call pulse count so the JSON response fits within the model's
        // ~8K output budget. Each pulse uses ~250-400 tokens; 14 stays safely
        // under the limit even with verbose howTos. Higher totals are reached
        // by BATCHING multiple calls (see generatePulsesAndWait).
        let pulseCount = max(1, min(count, 14))

        let languageInstruction = LocalizationManager.shared.aiLanguageInstruction
        let systemPrompt = """
        You are Pulse, an expert goal-achievement coach. You build idiot-proof
        roadmaps where every pulse is so specific that a complete beginner can
        execute it without asking a question.

        Every "howTo" is a recipe — numbered steps with concrete quantities,
        durations, and tools. Never use emojis. Return ONLY a single JSON
        object. No prose before or after.\(languageInstruction.isEmpty ? "" : "\n" + languageInstruction + " Every title, howTo, and proofRequired must be in the user's language.")
        """

        let userPrompt = """
        Build a personalized roadmap. Output JSON ONLY (no fences, no prose).

        GOAL: \(snapshot.title)
        FULL CONTEXT: \(snapshot.description.isEmpty ? "(none)" : snapshot.description)
        CATEGORY: \(snapshot.category)
        DEADLINE: \(snapshot.daysUntilDeadline) days
        TIME PER DAY: \(snapshot.timePerDay) min
        MOTIVATION: \(snapshot.motivation)/10
        SKILL LEVEL: \(snapshot.skillLevel)
        OBSTACLES: \(snapshot.obstacles.isEmpty ? "none" : snapshot.obstacles)

        Use EVERY detail from FULL CONTEXT to personalize. If money, treat the
        target amount, monetization style, weekly hours, and starting position
        as hard constraints. Don't give generic "freelancing" advice when the
        user picked SaaS or trading. If skill-related, anchor on the named
        skill and the current → target level gap.
        \((extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? "USER'S CUSTOM INSTRUCTIONS — follow these above all else, reshape the whole plan around them:\n\(extraInstructions!)" : "")

        RULES:
        - Generate EXACTLY \(pulseCount) pulses.
        - 80%+ must be DIRECT practice of the actual goal. No wellness padding.
        - Day 1 has a real goal-related action.
        - Spread scheduledDayOffset across the \(snapshot.daysUntilDeadline) days.
        - Order chronologically, ramp difficulty.
        - Probability of success: \(probability)%.

        EACH PULSE:
        - title: specific action, under 60 chars
        - howTo: 50-90 words. Numbered steps. Include tools, quantities,
                 common mistakes, and "you're done when..."
        - proofRequired: what the user shows to prove it's done (1 sentence)
        - proofType: "text" | "photo" | "number"
        - estimatedMinutes: int, roughly \(snapshot.timePerDay)
        - scheduledDayOffset: int (0 = today, 1 = tomorrow, …)

        OUTPUT THIS EXACT JSON SHAPE:
        {
          "probabilityScore": \(probability),
          "fastestPath": "<one sentence>",
          "pulses": [
            {
              "stepNumber": 1,
              "title": "...",
              "howTo": "1. ...\\n2. ...\\n3. ...",
              "proofRequired": "...",
              "proofType": "text",
              "estimatedMinutes": \(snapshot.timePerDay),
              "scheduledDayOffset": 0
            }
          ]
        }
        """

        let raw = try await AIRouter.shared.sendMessageJSON(
            userMessage: userPrompt,
            systemPrompt: systemPrompt,
            temperature: 0.5,
            maxTokens: 7000
        )

        // ROBUST EXTRACTION — the AI sometimes wraps JSON in prose or fences.
        // Walk braces from the first `{` to its matching `}` so we don't lose
        // a valid payload to a stray "Here's the plan:" prefix.
        let cleaned = Self.extractFirstJSONObject(raw)
        guard !cleaned.isEmpty,
              let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            print("[AIPulseGenerator] No parseable JSON. Raw response:\n\(raw.prefix(800))")
            #endif
            throw NSError(domain: "AIPulseGenerator", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "AI returned invalid JSON"])
        }

        let pulses = (json["pulses"] as? [[String: Any]] ?? []).compactMap { dict -> AIRoadmapPlan.Pulse? in
            guard let title = dict["title"] as? String else { return nil }
            return AIRoadmapPlan.Pulse(
                stepNumber: dict["stepNumber"] as? Int ?? 0,
                title: title,
                howTo: dict["howTo"] as? String ?? "",
                proofRequired: dict["proofRequired"] as? String ?? "Describe what you did.",
                proofType: dict["proofType"] as? String ?? "text",
                estimatedMinutes: dict["estimatedMinutes"] as? Int ?? snapshot.timePerDay,
                scheduledDayOffset: dict["scheduledDayOffset"] as? Int ?? 0
            )
        }

        return AIRoadmapPlan(
            probabilityScore: json["probabilityScore"] as? Int ?? probability,
            fastestPath: json["fastestPath"] as? String ?? "",
            skillGaps: json["skillGaps"] as? [String] ?? [],
            requiredHabits: json["requiredHabits"] as? [String] ?? [],
            pulses: pulses
        )
    }

    // MARK: - Save back to Core Data

    private func savePulses(plan: AIRoadmapPlan, forGoalWithID objectID: NSManagedObjectID) async {
        // Empty plan → just update metadata so we don't wipe an existing plan
        // with nothing. ANY non-empty plan is accepted — no arbitrary minimum.
        guard !plan.pulses.isEmpty else {
            #if DEBUG
            print("[AIPulseGenerator] AI returned 0 pulses — keeping existing intact.")
            #endif
            await updateMetadataOnly(plan: plan, forGoalWithID: objectID)
            return
        }

        let ctx = PersistenceController.shared.newBackgroundContext()
        await ctx.perform {
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return }
            goal.aiProbabilityScore = Float(plan.probabilityScore)
            goal.fastestPathSummary = plan.fastestPath

            // Replace fallbacks with the AI plan now that we know it's real.
            if let existing = goal.dailyTasks as? Set<DailyTask> {
                existing.forEach { ctx.delete($0) }
            }

            for (i, p) in plan.pulses.enumerated() {
                let task = DailyTask(context: ctx)
                task.id = UUID()
                task.title = p.title
                task.taskDescription = p.howTo
                task.howToDescription = p.howTo
                task.proofType = p.proofType
                task.proofDescription = p.proofRequired
                task.stepNumber = Int16(clamping: p.stepNumber == 0 ? i + 1 : p.stepNumber)
                task.sortOrder = Int16(clamping: i)
                task.estimatedMinutes = Int16(clamping: p.estimatedMinutes)
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: p.scheduledDayOffset, to: Date())
                task.xpReward = 10
                task.verificationStatus = "pending"
                task.isCompleted = false
                task.goal = goal
            }

            try? ctx.save()

            Task { @MainActor in
                WidgetDataService.shared.updateWidgets(context: PersistenceController.shared.container.viewContext)
            }
        }
    }

    /// Update probability + fastestPath but leave existing (fallback) pulses
    /// untouched. Used when the AI returned a weak plan we don't trust.
    private func updateMetadataOnly(plan: AIRoadmapPlan, forGoalWithID objectID: NSManagedObjectID) async {
        let ctx = PersistenceController.shared.newBackgroundContext()
        await ctx.perform {
            guard let goal = try? ctx.existingObject(with: objectID) as? Goal else { return }
            if plan.probabilityScore > 0 {
                goal.aiProbabilityScore = Float(plan.probabilityScore)
            }
            if !plan.fastestPath.isEmpty {
                goal.fastestPathSummary = plan.fastestPath
            }
            try? ctx.save()
        }
    }

    /// Pull the first balanced JSON object out of a response that may have
    /// markdown fences, leading prose, or trailing chatter.
    static func extractFirstJSONObject(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```json") { t = String(t.dropFirst(7)) }
        else if t.hasPrefix("```") { t = String(t.dropFirst(3)) }
        if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

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
        return String(t[firstBrace...])
    }
}

// MARK: - Plain structs (Sendable so they cross actor boundaries cleanly)

struct GoalSnapshot: Sendable {
    let title: String
    let description: String          // full goalDescription — carries all the rich inputs
    let category: String
    let daysUntilDeadline: Int
    let timePerDay: Int
    let motivation: Int
    let skillLevel: String
    let obstacles: String

    init(from goal: Goal) {
        self.title = goal.title ?? ""
        self.description = goal.goalDescription ?? ""
        self.category = goal.category ?? "personal"
        if let deadline = goal.deadline {
            self.daysUntilDeadline = max(1, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 30)
        } else {
            self.daysUntilDeadline = 30
        }
        self.timePerDay = max(15, Int(goal.availableTimePerDay))
        self.motivation = max(1, min(10, Int(goal.motivationLevel)))
        self.skillLevel = goal.skillLevel ?? "beginner"
        self.obstacles = goal.obstacles ?? ""
    }
}

struct AIRoadmapPlan: Sendable {
    let probabilityScore: Int
    let fastestPath: String
    let skillGaps: [String]
    let requiredHabits: [String]
    let pulses: [Pulse]

    struct Pulse: Sendable {
        let stepNumber: Int
        let title: String
        let howTo: String
        let proofRequired: String
        let proofType: String
        let estimatedMinutes: Int
        let scheduledDayOffset: Int
    }
}
