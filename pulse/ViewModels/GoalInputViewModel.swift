import SwiftUI
import CoreData
import UserNotifications

@Observable
class GoalInputViewModel {
    var title = ""
    var selectedCategory: GoalCategory = .personal

    /// Flavor of goal flow (skill / project / standard) — set from GoalTypePicker.
    /// Drives the title-field placeholder and the AI prompt context.
    var flavor: String = UserDefaults.standard.string(forKey: "pulse_pending_goal_flavor") ?? ""

    // ── Project-flavor specific fields (used only when flavor == "project") ──

    /// One-sentence description of what "done" looks like.
    var projectEndState: String = ""

    /// Comma-separated list of major deliverables.
    var projectDeliverables: String = ""

    /// User-described phases, free-text.
    var projectPhases: String = ""

    /// Self-rated complexity (1 = trivial, 5 = grand, 10 = lifetime project).
    var projectComplexity: Double = 5
    var deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    var motivationLevel: Double = 7
    var timePerDay: Double = 60
    var budget = ""
    var skillLevel: SkillLevel = .beginner
    var currentProgressValue: Double = 0
    var obstacles = ""

    // Progress context (shown when currentProgressValue > 0)
    var whatDidYouDo = ""
    var whatNeedHelp = ""

    var isAnalyzing = false
    var loadingMessages: [String] = []
    var currentLoadingMessage = 0
    var analysisResult: GoalAnalysisResult?
    var analysisError: String?

    /// Set true when a save is blocked by the Free 1-active-goal cap, so the view
    /// can present the upgrade prompt. AI is free for everyone; this gates only the
    /// goal-count cap (Pro = unlimited goals).
    var showingUpgrade = false

    var currentStep = 0

    /// Project flow inserts one extra step (project-details) after Basics.
    private var extraStepsForFlavor: Int { flavor == "project" ? 1 : 0 }

    var totalSteps: Int {
        (hasProgressContext ? 5 : 4) + extraStepsForFlavor
    }

    /// Whether to show the "what did you do?" step
    var hasProgressContext: Bool { currentProgressValue > 0 }

    /// The step index for AI analysis (last step).
    /// Standard flow: 3 (no progress) or 4 (with progress).
    /// Project flow: shift by +1.
    var analysisStepIndex: Int {
        (hasProgressContext ? 4 : 3) + extraStepsForFlavor
    }

    var canProceed: Bool {
        switch currentStep {
        case 0: return !title.isEmpty
        default: return true
        }
    }

    private var daysUntilDeadline: Int {
        max(1, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 30)
    }

    func analyzeGoal() async {
        // Clear pending flavor flag now that we're using it
        UserDefaults.standard.removeObject(forKey: "pulse_pending_goal_flavor")

        // AI is free for everyone, so `hasAIGeneration` is always true and this
        // branch is unreachable. Kept as a defensive fallback: if AI were ever
        // unavailable, hand back an empty plan the user can fill in manually.
        if !SubscriptionManager.shared.hasAIGeneration {
            await MainActor.run {
                self.analysisResult = GoalAnalysisResult.manualEmpty()
                self.isAnalyzing = false
            }
            return
        }

        isAnalyzing = true
        analysisError = nil

        // Start loading message rotation
        loadingMessages = generateLoadingMessages()
        currentLoadingMessage = 0
        startLoadingMessageRotation()

        let stepCount = calculateStepCount()

        var progressContext = ""
        if currentProgressValue > 0 {
            progressContext = """

            IMPORTANT CONTEXT - USER IS \(Int(currentProgressValue))% DONE:
            What they've done so far: \(whatDidYouDo)
            What they need help with: \(whatNeedHelp)

            Since the user is already \(Int(currentProgressValue))% done, START the roadmap from where they are now. Don't include steps they've already completed. Focus on the remaining \(100 - Int(currentProgressValue))% of work.
            """
        }

        // Flavor hint shapes how the AI structures the plan.
        let flavorHint: String
        switch flavor {
        case "skill":
            flavorHint = """

            GOAL FLAVOR: Skill mastery
            This is a SKILL-LEARNING goal. The user wants to MASTER something.
            Build pulses that are deliberate-practice sessions — short focused drills
            that target ONE sub-skill each. Include theory review pulses, hands-on
            practice pulses, and weekly "test what you learned" checkpoints.
            Reference real tools / tutorials / books / courses if relevant.
            """
        case "project":
            flavorHint = """

            GOAL FLAVOR: Long-term project (multi-phase)
            This is a PROJECT goal — multi-phase, milestone-driven.

            USER-PROVIDED PROJECT DETAILS:
            - End state ("done" looks like): \(projectEndState.isEmpty ? "(not specified)" : projectEndState)
            - Key deliverables: \(projectDeliverables.isEmpty ? "(not specified)" : projectDeliverables)
            - Phases the user is thinking in: \(projectPhases.isEmpty ? "(let AI choose)" : projectPhases)
            - Complexity self-rating: \(Int(projectComplexity))/10

            Build pulses as distinct tasks that move the project forward.
            Group them by phases (e.g. research → planning → build → polish → ship).
            Each phase should have a milestone pulse at its end. Include checkpoint
            pulses every ~7-14 days. Be SPECIFIC about deliverables — each pulse
            should name what artifact it produces (a document, a code commit, a
            mockup, an outline, a recording, etc.).
            """
        default:
            flavorHint = ""
        }

        let prompt = """
        Analyze this goal and create an IDIOT-PROOF step-by-step roadmap. Respond in JSON format.

        Goal: \(title)
        Category: \(selectedCategory.displayName)
        Deadline: \(formattedDeadline) (\(daysUntilDeadline) days from now)
        Motivation: \(Int(motivationLevel))/10
        Time available: \(Int(timePerDay)) minutes/day
        Skill level: \(skillLevel.displayName)
        Current progress: \(Int(currentProgressValue))%
        Obstacles: \(obstacles)\(progressContext)\(flavorHint)

        IMPORTANT INSTRUCTIONS:
        1. Generate exactly \(stepCount) steps. Each step must be so simple and clear that ANYONE can follow it, regardless of experience.
        2. Every step MUST have:
           - A clear, specific title (what to do)
           - A "howTo" with exact instructions (like explaining to a 10-year-old)
           - A "proofRequired" describing what evidence proves this step is done
           - A "proofType": "text" (describe what you did), "photo" (take a picture), or "number" (enter a metric)
           - "estimatedMinutes": how long this step takes
        3. Steps must be in chronological order from start to finish.
        4. Break complex tasks into tiny, bite-sized actions. Never assume the user knows anything.
        5. Include setup steps (downloading apps, buying supplies, creating accounts, etc.)

        Respond with ONLY this JSON:
        {
            "probabilityScore": <0-100>,
            "realismAssessment": "<1-2 sentence assessment>",
            "fastestPath": "<brief description of fastest approach>",
            "skillGaps": ["<gap1>", "<gap2>"],
            "requiredHabits": ["<habit1>", "<habit2>"],
            "adjustedTimeline": "<recommendation if deadline needs adjustment>",
            "steps": [
                {
                    "stepNumber": 1,
                    "title": "<clear action title>",
                    "howTo": "<detailed idiot-proof instructions>",
                    "proofRequired": "<what proves this is done>",
                    "proofType": "text|photo|number",
                    "estimatedMinutes": <number>,
                    "isHighPriority": true/false
                }
            ]
        }

        Generate exactly \(stepCount) steps. Make every step crystal clear.
        """

        do {
            let languageInstruction = LocalizationManager.shared.aiLanguageInstruction
            let systemPrompt = """
            You are Pulse, an AI goal achievement system that creates IDIOT-PROOF roadmaps.
            Your roadmaps are so detailed and clear that even someone who has never done anything like this before can follow them perfectly.
            Every instruction must be specific, actionable, and impossible to misunderstand.
            Never use vague language like "practice" or "work on it" — always specify EXACTLY what to do, for how long, and how to know when it's done.
            Do NOT use emojis in any text content.
            Always respond in valid JSON.\(languageInstruction.isEmpty ? "" : "\n" + languageInstruction + "\nAll step titles and descriptions in the JSON must be in the user's language.")
            """

            let response = try await GeminiAPIService.shared.sendMessageJSON(
                userMessage: prompt,
                systemPrompt: systemPrompt,
                temperature: 0.5,
                maxTokens: 8192
            )

            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let steps = parseSteps(json["steps"])
                // AI-ONLY: never fabricate pulses. If the AI returned no usable
                // steps, surface an error and create nothing.
                if steps.isEmpty {
                    analysisError = "The AI didn't return any steps. This is usually a brief hiccup — tap Retry. If it keeps happening, try a shorter, clearer goal title."
                    analysisResult = nil
                } else {
                    analysisResult = GoalAnalysisResult(
                        probabilityScore: json["probabilityScore"] as? Int ?? 50,
                        realismAssessment: json["realismAssessment"] as? String ?? "Analysis complete.",
                        fastestPath: json["fastestPath"] as? String ?? "Follow the generated roadmap.",
                        skillGaps: json["skillGaps"] as? [String] ?? [],
                        requiredHabits: json["requiredHabits"] as? [String] ?? [],
                        adjustedTimeline: json["adjustedTimeline"] as? String,
                        steps: steps
                    )
                }
            } else {
                // Unparseable AI response — fabricate nothing.
                analysisError = "The AI's response was incomplete. Tap Retry — this usually works on the second attempt."
                analysisResult = nil
            }
        } catch {
            // Map known errors to friendly copy; never surface a raw server body.
            // GeminiDirectError / AIRouterError already provide vetted, user-facing
            // descriptions (rate-limit → "Usage limit reached", etc.). Offline
            // URLErrors get a clear connectivity message. Anything else falls back
            // to a generic retry prompt.
            if let urlError = error as? URLError,
               [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                .dataNotAllowed].contains(urlError.code) {
                analysisError = "There's no internet connection. Try again."
            } else if let geminiError = error as? GeminiDirectError {
                analysisError = geminiError.errorDescription ?? "Pulse AI hit a snag. Tap Retry."
            } else if let routerError = error as? AIRouterError {
                analysisError = routerError.errorDescription ?? "Pulse AI hit a snag. Tap Retry."
            } else {
                analysisError = "Pulse AI hit a snag. Tap Retry."
            }
            analysisResult = nil
        }

        isAnalyzing = false
    }

    private func calculateStepCount() -> Int {
        // Single source of truth shared with simulator seed.
        // motivation × time/day × deadline → number of pulses
        return AIPulseGenerator.recommendedPulseCount(
            motivation: Int(motivationLevel),
            timePerDayMinutes: Int(timePerDay),
            daysUntilDeadline: daysUntilDeadline
        )
    }

    private func parseSteps(_ raw: Any?) -> [RoadmapStep] {
        // AI-ONLY: if the AI didn't return a steps array, return nothing.
        // The caller turns an empty result into a visible error — we never
        // fabricate precoded pulses.
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let stepNumber = dict["stepNumber"] as? Int,
                  let title = dict["title"] as? String else { return nil }
            return RoadmapStep(
                stepNumber: stepNumber,
                title: title,
                howTo: dict["howTo"] as? String ?? "Complete this pulse as described.",
                proofRequired: dict["proofRequired"] as? String ?? "Describe what you did.",
                proofType: dict["proofType"] as? String ?? "text",
                estimatedMinutes: dict["estimatedMinutes"] as? Int ?? 15,
                isHighPriority: dict["isHighPriority"] as? Bool ?? false
            )
        }
    }

    /// Count of currently-active goals in the given context. Treats a nil/empty
    /// status as active (matching Goal.statusEnum's coercion) so the cap can't be
    /// bypassed by legacy rows. Used by the save-site goal-cap backstop.
    private func activeGoalCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Goal>(entityName: "Goal")
        request.predicate = NSPredicate(
            format: "status == %@ OR status == %@ OR status == nil",
            GoalStatus.active.rawValue, ""
        )
        return (try? context.count(for: request)) ?? 0
    }

    func saveGoal(context: NSManagedObjectContext) -> Goal {
        let goal = Goal(context: context)

        // Authoritative goal-cap backstop at the save site (the UI entry points
        // also check, but this is the single chokepoint). AI is free for everyone;
        // this only enforces the Free 1-active-goal cap (Pro = unlimited goals).
        let currentActiveCount = activeGoalCount(in: context)
        guard SubscriptionManager.shared.canCreateGoal(currentCount: currentActiveCount) else {
            showingUpgrade = true
            context.delete(goal)
            return goal
        }

        goal.id = UUID()
        goal.title = title
        goal.goalDescription = title
        goal.category = selectedCategory.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.deadline = deadline
        goal.currentProgress = Float(currentProgressValue)
        goal.aiProbabilityScore = Float(analysisResult?.probabilityScore ?? 50)
        goal.motivationLevel = Int16(motivationLevel)
        goal.skillLevel = skillLevel.rawValue
        goal.availableTimePerDay = Float(timePerDay)
        goal.obstacles = obstacles
        goal.createdAt = Date()

        let profile = UserProfile.fetchOrCreate(in: context)
        goal.userProfile = profile

        // Create steps from AI roadmap
        if let steps = analysisResult?.steps {
            // Calculate how many pulses to mark as already completed based on current progress
            let stepsToComplete = Int(Double(steps.count) * currentProgressValue / 100.0)

            for step in steps {
                let task = DailyTask(context: context)
                task.id = UUID()
                task.title = step.title
                task.howToDescription = step.howTo
                task.proofDescription = step.proofRequired
                task.proofType = step.proofType
                task.stepNumber = Int16(clamping: step.stepNumber)
                task.sortOrder = Int16(clamping: step.stepNumber)
                task.estimatedMinutes = Int16(clamping: step.estimatedMinutes)
                task.isHighPriority = step.isHighPriority
                task.xpReward = 10
                task.verificationStatus = "pending"
                task.goal = goal

                // Mark early steps as completed based on current progress
                if step.stepNumber <= stepsToComplete {
                    task.isCompleted = true
                    task.completedDate = Date()
                } else {
                    task.isCompleted = false
                }

                // Schedule steps across the timeline
                let daysPerStep = max(1, daysUntilDeadline / max(steps.count, 1))
                let dayOffset = (step.stepNumber - 1) * daysPerStep
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())
            }

            // Create milestone markers at every ~20% of steps
            // Use days-based labels instead of weeks when goal is short
            let milestoneInterval = max(steps.count / 5, 1)
            let useWeeks = daysUntilDeadline > 14
            for i in stride(from: milestoneInterval, through: steps.count, by: milestoneInterval) {
                let milestone = Milestone(context: context)
                milestone.id = UUID()
                let pct = Int(Double(i) / Double(steps.count) * 100)
                milestone.title = i >= steps.count ? "Goal Complete!" : "\(pct)% — Pulses 1-\(i) done"
                milestone.sortOrder = Int16(i / milestoneInterval)
                let dayIndex = i * daysUntilDeadline / max(steps.count, 1)
                if useWeeks {
                    milestone.weekNumber = Int16(dayIndex / 7 + 1)
                } else {
                    // For short goals, weekNumber stores day number instead
                    milestone.weekNumber = Int16(dayIndex + 1)
                }
                milestone.xpReward = 50
                milestone.isCompleted = false
                milestone.goal = goal
            }
        }

        // Store roadmap JSON for reference
        if let steps = analysisResult?.steps,
           let jsonData = try? JSONSerialization.data(withJSONObject: steps.map { step in
               ["stepNumber": step.stepNumber, "title": step.title, "howTo": step.howTo, "proofRequired": step.proofRequired, "proofType": step.proofType] as [String : Any]
           }),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            goal.aiRoadmapJSON = jsonString
        }

        try? context.save()
        WidgetDataService.shared.updateWidgets(context: context)

        // A goal now exists -> drop the "start a goal" nudge and (re)build the
        // adaptive goal notifications immediately, rather than waiting for the
        // next app foreground. AdaptiveNotificationScheduler owns ALL reminders —
        // do not schedule a second set with scheduleCheckInNotifications.
        AdaptiveNotificationScheduler.shared.refreshFromSettings()

        // Mirror to the user's private iCloud (CloudKit) via the sync service.
        Task {
            try? await FirestoreSyncService.shared.syncGoal(goal)
        }

        return goal
    }

    private func scheduleCheckInNotifications(for goal: Goal) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Daily check-in notification
        let content = UNMutableNotificationContent()
        content.title = "Pulse Check-In"
        content.body = "How's your progress on \"\(goal.titleValue)\"? Open the app to complete your next pulse!"
        content.sound = .default

        // Fire daily at 10 AM
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "checkin-\(goal.id?.uuidString ?? UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request)

        // Evening reminder at 8 PM
        let eveningContent = UNMutableNotificationContent()
        eveningContent.title = "Don't break your streak!"
        eveningContent.body = "You haven't completed today's pulse yet. Keep your momentum going!"
        eveningContent.sound = .default

        var eveningComponents = DateComponents()
        eveningComponents.hour = 20
        eveningComponents.minute = 0
        let eveningTrigger = UNCalendarNotificationTrigger(dateMatching: eveningComponents, repeats: true)

        let eveningRequest = UNNotificationRequest(
            identifier: "evening-\(goal.id?.uuidString ?? UUID().uuidString)",
            content: eveningContent,
            trigger: eveningTrigger
        )
        center.add(eveningRequest)
    }

    private var formattedDeadline: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: deadline)
    }

    private func generateLoadingMessages() -> [String] {
        [
            "Analyzing your goal parameters...",
            "Calculating optimal timeline...",
            "Mapping skill requirements...",
            "Generating step-by-step roadmap...",
            "Estimating probability of success...",
            "Identifying potential obstacles...",
            "Optimizing pulse schedule...",
            "Building your personalized plan...",
            "Cross-referencing best practices...",
            "Finalizing your roadmap...",
            "Calibrating difficulty curve...",
            "Assigning time estimates...",
            "Almost there..."
        ]
    }

    private func startLoadingMessageRotation() {
        Task { @MainActor in
            while isAnalyzing && currentLoadingMessage < loadingMessages.count - 1 {
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                if isAnalyzing {
                    currentLoadingMessage += 1
                }
            }
        }
    }
}

// MARK: - Data Models

struct GoalAnalysisResult {
    let probabilityScore: Int
    let realismAssessment: String
    let fastestPath: String
    let skillGaps: [String]
    let requiredHabits: [String]
    let adjustedTimeline: String?
    let steps: [RoadmapStep]

    // Backward compat
    var weeklyMilestones: [WeeklyMilestone] {
        // Group steps into weekly milestones for preview
        let stepsPerWeek = max(steps.count / 4, 1)
        var milestones: [WeeklyMilestone] = []
        for week in 0..<4 {
            let start = week * stepsPerWeek
            let end = min(start + stepsPerWeek, steps.count)
            if start < steps.count {
                let weekSteps = Array(steps[start..<end])
                milestones.append(WeeklyMilestone(
                    week: week + 1,
                    title: weekSteps.first?.title ?? "Week \(week + 1)",
                    tasks: weekSteps.prefix(3).map { $0.title }
                ))
            }
        }
        return milestones
    }

    /// Empty fallback plan used only if AI is ever unavailable (AI is free for
    /// everyone, so this normally never runs). The user adds their own steps on
    /// the goal detail screen and gets daily check-in reminders.
    static func manualEmpty() -> GoalAnalysisResult {
        GoalAnalysisResult(
            probabilityScore: 50,
            realismAssessment: "Add your own steps below and check in daily. You can also let Pulse build an AI plan for you — it's free.",
            fastestPath: "Break your goal into a few concrete steps you can do.",
            skillGaps: [],
            requiredHabits: [],
            adjustedTimeline: nil,
            steps: []
        )
    }
}

struct RoadmapStep {
    let stepNumber: Int
    let title: String
    let howTo: String
    let proofRequired: String
    let proofType: String // "text", "photo", "number"
    let estimatedMinutes: Int
    let isHighPriority: Bool
}

struct WeeklyMilestone {
    let week: Int
    let title: String
    let tasks: [String]
}
