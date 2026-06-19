import Foundation
import CoreData
import WidgetKit

// MARK: - MentorAgent
//
// The app-controlling AI. Where `AIRouter.sendMessage` is a one-shot chat turn,
// MentorAgent runs a full DeepSeek tool-calling loop so the mentor chat can
// actually OPERATE Pulse on the user's behalf: add / edit / delete pulses,
// rebuild the remainder of a plan ("start from where I'm holding"), regenerate
// the whole plan, reshape the goal itself, and search the live web to ground its
// answers in real information instead of hallucinating.
//
// Flow per user turn:
//   1. Build a system prompt = personality voice + tool guidance + a NUMBERED
//      snapshot of the goal's pulses (so the model can reference "pulse 3").
//   2. Loop: ask DeepSeek with the tool schemas. If it returns text, that's the
//      reply. If it returns tool calls, execute them against Core Data / the web,
//      feed the results back, and ask again. Capped at `maxRounds`; the final
//      round forces a text-only answer so the turn always terminates.
//   3. Return the reply plus a list of human-readable action labels (what it did).
//
// Requires a DeepSeek key (tool calling is not on the transitional Groq bridge);
// callers should gate on `AIRouter.shared.toolCallingAvailable`.

struct MentorAgentOutcome: Sendable {
    let reply: String
    /// Human-readable summary of every mutation the agent performed this turn,
    /// e.g. ["Added a pulse", "Deleted pulse 3"]. Empty when nothing changed.
    let actions: [String]
    var didMutate: Bool { !actions.isEmpty }
}

final class MentorAgent: @unchecked Sendable {
    static let shared = MentorAgent()
    private init() {}

    /// Hard cap on tool-calling rounds so a confused model can't loop forever and
    /// burn the daily budget. EACH round is one upstream API call, so this also
    /// directly bounds requests-per-message — the main driver of hitting Gemini's
    /// free-tier rate limit. 3 is plenty for the real flows (decide → act → answer)
    /// while cutting worst-case calls per chat in half. The last round forces a
    /// text-only answer.
    private let maxRounds = 3
    /// Set by create_goal so the SAME turn can keep operating on the brand-new
    /// goal (add_pulse, etc.) even though the turn started with no goal selected.
    private var lastCreatedGoalID: NSManagedObjectID?

    // MARK: - Public entry point

    /// Run one mentor turn. `personalityPrompt` is the raw personality system
    /// prompt; the agent appends its own tool guidance + goal snapshot. Pass the
    /// selected goal's `objectID` (nil = no goal selected → chat + web_search only).
    func run(
        userMessage: String,
        personalityPrompt: String,
        history: [(role: String, content: String)],
        goalObjectID: NSManagedObjectID?
    ) async throws -> MentorAgentOutcome {
        var messages: [[String: Any]] = []
        let system = await buildSystemPrompt(personalityPrompt: personalityPrompt, goalObjectID: goalObjectID)
        messages.append(["role": "system", "content": system])
        for h in history.suffix(20) {
            let role = (h.role == "assistant" || h.role == "model") ? "assistant" : "user"
            messages.append(["role": role, "content": h.content])
        }
        messages.append(["role": "user", "content": userMessage])

        var actionLabels: [String] = []
        // Tracks the goal the agent is operating on. Starts as the selected goal
        // (may be nil); create_goal sets it so subsequent tools in this turn work.
        var activeGoalID = goalObjectID
        let tools = Self.toolSchemas

        for round in 0..<maxRounds {
            let isLastRound = round == maxRounds - 1
            let result = try await AIRouter.shared.chatWithTools(
                messages: messages,
                tools: tools,
                toolChoice: isLastRound ? "none" : "auto",
                temperature: 0.6,
                maxTokens: 4096
            )

            // No tool calls → the model produced its final answer.
            if result.toolCalls.isEmpty {
                let reply = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return MentorAgentOutcome(
                    reply: reply.isEmpty ? Self.emptyReplyFallback(didMutate: !actionLabels.isEmpty) : reply,
                    actions: actionLabels
                )
            }

            // Append the assistant's tool-call message verbatim, then run each call.
            messages.append(Self.normalizedAssistantMessage(result.rawAssistantMessage))

            // Resolve pulse numbers against a snapshot taken BEFORE this round's
            // mutations, so multiple structural edits in one round all refer to the
            // numbering the model was shown — not a list shifting under its feet.
            let roundPulseIDs = await orderedPulseIDs(activeGoalID)

            for call in result.toolCalls {
                let (json, label) = await execute(call: call, goalObjectID: activeGoalID, roundPulseIDs: roundPulseIDs)
                if let label { actionLabels.append(label) }
                // If the model just created a goal, operate on it for the rest of
                // this turn (so create_goal → add_pulse works in one breath).
                if let created = lastCreatedGoalID { activeGoalID = created; lastCreatedGoalID = nil }
                messages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": json
                ])
            }
        }

        // Rounds exhausted while still calling tools — force a final text wrap-up.
        let wrapUp = try await AIRouter.shared.chatWithTools(
            messages: messages, tools: tools, toolChoice: "none",
            temperature: 0.6, maxTokens: 2048
        )
        let reply = wrapUp.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return MentorAgentOutcome(
            reply: reply.isEmpty ? Self.emptyReplyFallback(didMutate: !actionLabels.isEmpty) : reply,
            actions: actionLabels
        )
    }

    // MARK: - System prompt

    @MainActor
    private func buildSystemPrompt(personalityPrompt: String, goalObjectID: NSManagedObjectID?) -> String {
        let webSearchAvailable = WebSearchService.shared.isConfigured
        let noGoalChatVerb = webSearchAvailable ? "chat, use web_search," : "chat"
        var goalBlock = """
        NO GOAL IS SELECTED right now. You can \(noGoalChatVerb) and — when the
        user describes something they want to achieve — CREATE it with create_goal,
        then immediately lay out its first steps with add_pulse. (The edit/delete/
        complete pulse tools act on a selected or newly-created goal.)
        """

        if let goalID = goalObjectID,
           let goal = try? PersistenceController.shared.container.viewContext.existingObject(with: goalID) as? Goal {
            let all = goal.dailyTasksArray
            let done = all.filter { $0.isCompleted }.count
            let pct = all.isEmpty ? 0 : Int(Double(done) / Double(all.count) * 100)

            var lines: [String] = []
            for (i, t) in all.enumerated() {
                let box = t.isCompleted ? "[x]" : "[ ]"
                let mins = Int(t.estimatedMinutes)
                let day = t.scheduledDate.map { Self.dayLabel(for: $0) } ?? "unscheduled"
                lines.append("\(i + 1). \(box) \(t.title ?? "Untitled") — \(mins)m, \(day)")
            }
            let pulseList = lines.isEmpty ? "(no pulses yet — build some with add_pulse or regenerate_entire_plan)" : lines.joined(separator: "\n")

            goalBlock = """
            SELECTED GOAL: "\(goal.titleValue)"
            Category: \(goal.categoryEnum.displayName)
            Progress: \(pct)% (\(done)/\(all.count) pulses completed)
            Days remaining: \(goal.daysRemaining)
            Motivation: \(goal.motivationLevel)/10
            Skill level: \(goal.skillLevel ?? "unspecified")
            Obstacles: \(goal.obstacles ?? "none noted")

            CURRENT PULSES — numbered. Use these 1-based numbers for edit_pulse,
            delete_pulse and complete_pulse:
            \(pulseList)
            """
        }

        // Strip web_search references from the tool playbook when the tool
        // isn't registered, so the model doesn't try to call a tool that isn't
        // there. The bullet sits on its own line; removing it is a no-op
        // otherwise.
        var guidance = Self.toolGuidance
        if !webSearchAvailable {
            guidance = guidance
                .replacingOccurrences(
                    of: "    - web_search: for ANY question that needs real, current, or factual information\n      (prices, news, how-to facts, specs, \"what's the best…\"), search first and\n      base your answer ONLY on what the results say. Never invent facts.\n",
                    with: ""
                )
                .replacingOccurrences(
                    of: " Use web_search ONLY\n      for genuinely current/external facts (prices, latest research, specific products).",
                    with: ""
                )
        }
        return personalityPrompt + "\n\n" + guidance + "\n\n" + goalBlock
    }

    private static let toolGuidance = """
    YOU CAN OPERATE THIS APP. You are not a passive chatbot — you have tools that
    directly change the user's plan and goal in Pulse. When the user asks you to
    change something, DO IT with a tool; don't just describe what they could do.

    Pulses are the concrete daily action steps of a goal. They are numbered in the
    list below (1-based, top to bottom). Always reference that numbering.

    Tool playbook:
    - create_goal: when the user wants to start something NEW and no goal is open,
      create it first, then immediately add_pulse several times to build the plan.
    - add_pulse: add a new action step. Write a recipe-quality howTo (numbered
      sub-steps, quantities, tools, and a "done when…" line).
    - edit_pulse / delete_pulse: change or remove a specific pulse by its number.
    - complete_pulse: mark a pulse done when the user says they finished it.
    - regenerate_remaining_pulses: the user finished some pulses and wants the REST
      rebuilt ("start from where I'm holding"). Keeps completed pulses, replaces the
      rest. Pass the user's instructions.
    - regenerate_entire_plan: throw out the plan and build a fresh one. Pass the
      user's instructions.
    - change_goal: edit the goal's title, description, deadline, or motivation.
    - web_search: for ANY question that needs real, current, or factual information
      (prices, news, how-to facts, specs, "what's the best…"), search first and
      base your answer ONLY on what the results say. Never invent facts.

    Rules:
    - After a structural change the pulse numbers shift. If you need to make further
      edits, call get_goal_state to see the fresh numbering before acting.
    - Only the tools change the app. NEVER claim you added/changed/deleted something
      unless the matching tool call succeeded.
    - You answer fitness, nutrition, training, and goal questions — and produce full
      meal plans and workout routines — DIRECTLY from your own knowledge. You do NOT
      need a tool for that, and you do NOT need a selected goal. Use web_search ONLY
      for genuinely current/external facts (prices, latest research, specific products).
    - Reply length matches the request. Confirm an ACTION you took in 1-3 sentences.
      But when the user asks for information, a plan, or advice — a meal plan, a
      workout, an explanation — give the COMPLETE, well-structured answer (short
      headers, bullet or numbered lists, real numbers / foods / exercises); never
      shrink it into a teaser. Always in your personality's exact voice. No JSON, no
      tool talk.
    """

    // MARK: - Tool schemas (OpenAI function-calling format)

    private static var toolSchemas: [[String: Any]] {
        func fn(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
            [
                "type": "function",
                "function": [
                    "name": name,
                    "description": description,
                    "parameters": [
                        "type": "object",
                        "properties": properties,
                        "required": required
                    ]
                ]
            ]
        }
        let proofTypeProp: [String: Any] = [
            "type": "string",
            "enum": ["text", "photo", "number"],
            "description": "How the user proves the pulse is done."
        ]
        // Only expose web_search to the model when a Tavily key is actually
        // configured. Otherwise it would dangle a tool that always returns
        // "Search isn't available." — the model just wastes a turn calling it.
        let webSearchAvailable = WebSearchService.shared.isConfigured
        var allTools: [[String: Any]] = []
        allTools.append(contentsOf: [
            fn("create_goal",
               "Create a brand-NEW goal from scratch. Use when the user describes something they want to achieve and no goal is open. AFTER creating it, immediately use add_pulse (several times) to lay out its first action steps.",
               [
                   "title": ["type": "string", "description": "Short goal title, under 60 chars."],
                   "description": ["type": "string", "description": "1-2 sentence description / context for the goal."],
                   "category": [
                       "type": "string",
                       "enum": ["fitness", "learning", "finance", "career", "health", "creative", "social", "mindfulness", "personal"],
                       "description": "Best-fit category."
                   ],
                   "deadlineDays": ["type": "integer", "description": "Target deadline in days from today (default 30 if unsure)."],
                   "motivation": ["type": "integer", "description": "Motivation level 1-10 (default 7)."]
               ],
               required: ["title"]),

            fn("get_goal_state",
               "Get the goal's current details and the up-to-date NUMBERED list of pulses. Call this after structural edits to re-ground on the new numbering.",
               [:]),

            fn("add_pulse",
               "Add one new pulse (action step) to the selected goal.",
               [
                   "title": ["type": "string", "description": "Specific action, under 60 chars."],
                   "howTo": ["type": "string", "description": "Numbered recipe steps: quantities, tools, common mistakes, and a 'done when…' line."],
                   "proofRequired": ["type": "string", "description": "One sentence: what the user shows to prove it's done."],
                   "proofType": proofTypeProp,
                   "estimatedMinutes": ["type": "integer", "description": "Rough minutes to complete."],
                   "dayOffset": ["type": "integer", "description": "Days from today to schedule it (0 = today, 1 = tomorrow…)."]
               ],
               required: ["title", "howTo"]),

            fn("edit_pulse",
               "Edit an existing pulse, identified by its 1-based number. Only the fields you pass are changed.",
               [
                   "pulse_number": ["type": "integer", "description": "1-based pulse number from the list."],
                   "title": ["type": "string"],
                   "howTo": ["type": "string"],
                   "proofRequired": ["type": "string"],
                   "proofType": proofTypeProp,
                   "estimatedMinutes": ["type": "integer"]
               ],
               required: ["pulse_number"]),

            fn("delete_pulse",
               "Delete the pulse with the given 1-based number.",
               [
                   "pulse_number": ["type": "integer", "description": "1-based pulse number from the list."]
               ],
               required: ["pulse_number"]),

            fn("complete_pulse",
               "Mark the pulse with the given 1-based number as completed.",
               [
                   "pulse_number": ["type": "integer", "description": "1-based pulse number from the list."]
               ],
               required: ["pulse_number"]),

            fn("regenerate_remaining_pulses",
               "Keep every COMPLETED pulse and rebuild only the unfinished remainder of the plan with fresh AI-generated pulses. Use when the user wants to 'start from where I am' or redo the rest.",
               [
                   "instructions": ["type": "string", "description": "The user's guidance for the rebuilt remainder."],
                   "count": ["type": "integer", "description": "Roughly how many new pulses to generate (optional)."]
               ]),

            fn("regenerate_entire_plan",
               "Discard the current plan entirely and generate a brand-new full roadmap of pulses for the goal.",
               [
                   "instructions": ["type": "string", "description": "The user's guidance for the new plan."],
                   "count": ["type": "integer", "description": "Roughly how many pulses to generate (optional)."]
               ]),

            fn("change_goal",
               "Edit the goal itself. Only the fields you pass are changed.",
               [
                   "title": ["type": "string"],
                   "description": ["type": "string", "description": "The detailed goal description / context."],
                   "deadlineDays": ["type": "integer", "description": "New deadline, in days from today."],
                   "motivation": ["type": "integer", "description": "Motivation level 1-10."]
               ])
        ])
        if webSearchAvailable {
            allTools.append(
                fn("web_search",
                   "Search the live web for real, current information and return the top findings. Use for any factual / current question, then base your answer on the results.",
                   [
                       "query": ["type": "string", "description": "The search query."]
                   ],
                   required: ["query"])
            )
        }
        return allTools
    }

    // MARK: - Tool execution

    private func execute(
        call: DeepSeekToolCall,
        goalObjectID: NSManagedObjectID?,
        roundPulseIDs: [NSManagedObjectID]
    ) async -> (json: String, label: String?) {
        let args = Self.parseArgs(call.argumentsJSON)

        switch call.name {
        case "get_goal_state":
            let state = await goalStateJSON(goalObjectID: goalObjectID)
            return (state, nil)

        case "web_search":
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return (Self.errJSON("Empty query."), nil) }
            do {
                let findings = try await WebSearchService.shared.search(query: query)
                let capped = String(findings.prefix(4000))
                return (Self.jsonString(["ok": true, "query": query, "results": capped]), "Searched the web")
            } catch {
                return (Self.jsonString(["ok": false, "error": error.localizedDescription]), nil)
            }

        case "create_goal":
            return await createGoal(args: args)

        case "add_pulse":
            guard let goalID = goalObjectID else { return (Self.errJSON("No goal selected."), nil) }
            return await addPulse(goalID: goalID, args: args)

        case "edit_pulse":
            guard goalObjectID != nil else { return (Self.errJSON("No goal selected."), nil) }
            guard let id = pulseID(from: args, roundPulseIDs: roundPulseIDs) else {
                return (Self.errJSON("No such pulse number. There are \(roundPulseIDs.count) pulses."), nil)
            }
            return await editPulse(taskID: id.objectID, number: id.number, goalObjectID: goalObjectID, args: args)

        case "delete_pulse":
            guard goalObjectID != nil else { return (Self.errJSON("No goal selected."), nil) }
            guard let id = pulseID(from: args, roundPulseIDs: roundPulseIDs) else {
                return (Self.errJSON("No such pulse number. There are \(roundPulseIDs.count) pulses."), nil)
            }
            return await deletePulse(taskID: id.objectID, number: id.number, goalObjectID: goalObjectID)

        case "complete_pulse":
            guard goalObjectID != nil else { return (Self.errJSON("No goal selected."), nil) }
            guard let id = pulseID(from: args, roundPulseIDs: roundPulseIDs) else {
                return (Self.errJSON("No such pulse number. There are \(roundPulseIDs.count) pulses."), nil)
            }
            return await completePulse(taskID: id.objectID, number: id.number, goalObjectID: goalObjectID)

        case "change_goal":
            guard let goalID = goalObjectID else { return (Self.errJSON("No goal selected."), nil) }
            return await changeGoal(goalID: goalID, args: args)

        case "regenerate_remaining_pulses":
            guard let goalID = goalObjectID else { return (Self.errJSON("No goal selected."), nil) }
            let instructions = args["instructions"] as? String
            let count = Self.intArg(args, "count") ?? 12
            let added = await AIPulseGenerator.shared.regenerateRemaining(
                forGoalWithID: goalID, requestedCount: count, extraInstructions: instructions
            )
            if added > 0 {
                return (Self.jsonString(["ok": true, "newPulses": added]), "Rebuilt the remaining plan (\(added) pulses)")
            }
            let err = AIPulseGenerator.shared.lastError ?? "AI couldn't rebuild the plan right now."
            return (Self.jsonString(["ok": false, "error": err]), nil)

        case "regenerate_entire_plan":
            guard let goalID = goalObjectID else { return (Self.errJSON("No goal selected."), nil) }
            let instructions = args["instructions"] as? String
            let count = Self.intArg(args, "count") ?? 20
            let ok = await AIPulseGenerator.shared.generatePulsesAndWait(
                forGoalWithID: goalID, requestedCount: count, extraInstructions: instructions
            )
            if ok {
                let total = await pulseCount(goalID: goalID)
                return (Self.jsonString(["ok": true, "totalPulses": total]), "Rebuilt the entire plan (\(total) pulses)")
            }
            let err = AIPulseGenerator.shared.lastError ?? "AI couldn't rebuild the plan right now."
            return (Self.jsonString(["ok": false, "error": err]), nil)

        default:
            return (Self.errJSON("Unknown tool \(call.name)."), nil)
        }
    }

    // MARK: - Core Data mutations (main-actor isolated)

    @MainActor
    private func createGoal(args: [String: Any]) -> (String, String?) {
        let ctx = PersistenceController.shared.container.viewContext
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return (Self.errJSON("A title is required to create a goal."), nil)
        }
        let goal = Goal(context: ctx)
        goal.id = UUID()
        goal.title = title
        goal.goalDescription = (args["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? title
        let category = (args["category"] as? String).flatMap { GoalCategory(rawValue: $0.lowercased()) } ?? .personal
        goal.category = category.rawValue
        goal.status = GoalStatus.active.rawValue
        let days = max(1, Self.intArg(args, "deadlineDays") ?? 30)
        goal.deadline = Calendar.current.date(byAdding: .day, value: days, to: Date())
        goal.currentProgress = 0
        goal.aiProbabilityScore = 60
        goal.motivationLevel = Int16(clamping: Self.intArg(args, "motivation") ?? 7)
        goal.createdAt = Date()
        goal.userProfile = UserProfile.fetchOrCreate(in: ctx)
        do {
            try ctx.save()
        } catch {
            return (Self.errJSON("Couldn't save the new goal: \(error.localizedDescription)"), nil)
        }
        lastCreatedGoalID = goal.objectID
        WidgetDataService.shared.updateWidgets(context: ctx)
        return (Self.jsonString([
            "ok": true,
            "createdGoal": title,
            "category": category.rawValue,
            "deadlineDays": days,
            "note": "Goal created and is now the active goal — build its plan now with add_pulse."
        ]), "Created a goal")
    }

    @MainActor
    private func addPulse(goalID: NSManagedObjectID, args: [String: Any]) -> (String, String?) {
        let ctx = PersistenceController.shared.container.viewContext
        guard let goal = try? ctx.existingObject(with: goalID) as? Goal else {
            return (Self.errJSON("Goal not found."), nil)
        }
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return (Self.errJSON("A title is required."), nil)
        }
        let existing = goal.dailyTasksArray
        let maxStep = existing.map { Int($0.stepNumber) }.max() ?? 0
        let howTo = args["howTo"] as? String ?? ""
        let dayOffset = Self.intArg(args, "dayOffset") ?? 0

        let task = DailyTask(context: ctx)
        task.id = UUID()
        task.title = title
        task.taskDescription = howTo
        task.howToDescription = howTo
        task.proofType = Self.normalizedProofType(args["proofType"] as? String)
        task.proofDescription = args["proofRequired"] as? String ?? "Describe what you did."
        task.stepNumber = Int16(clamping: maxStep + 1)
        task.sortOrder = Int16(clamping: existing.count)
        task.estimatedMinutes = Int16(clamping: Self.intArg(args, "estimatedMinutes") ?? 20)
        task.scheduledDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())
        task.xpReward = 10
        task.verificationStatus = "pending"
        task.isCompleted = false
        task.goal = goal

        try? ctx.save()
        WidgetDataService.shared.updateWidgets(context: ctx)
        fireGoalSync(goalID)
        return (Self.jsonString(["ok": true, "addedPulse": title, "newNumber": existing.count + 1]), "Added a pulse")
    }

    @MainActor
    private func editPulse(taskID: NSManagedObjectID, number: Int, goalObjectID: NSManagedObjectID?, args: [String: Any]) -> (String, String?) {
        let ctx = PersistenceController.shared.container.viewContext
        guard let task = try? ctx.existingObject(with: taskID) as? DailyTask else {
            return (Self.errJSON("Pulse not found."), nil)
        }
        var changed: [String] = []
        if let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            task.title = title; changed.append("title")
        }
        if let howTo = args["howTo"] as? String, !howTo.isEmpty {
            task.taskDescription = howTo; task.howToDescription = howTo; changed.append("howTo")
        }
        if let proof = args["proofRequired"] as? String, !proof.isEmpty {
            task.proofDescription = proof; changed.append("proof")
        }
        if let pt = args["proofType"] as? String {
            task.proofType = Self.normalizedProofType(pt); changed.append("proofType")
        }
        if let mins = Self.intArg(args, "estimatedMinutes") {
            task.estimatedMinutes = Int16(clamping: mins); changed.append("minutes")
        }
        guard !changed.isEmpty else { return (Self.errJSON("No fields to change were provided."), nil) }
        try? ctx.save()
        WidgetDataService.shared.updateWidgets(context: ctx)
        if let goalObjectID { fireGoalSync(goalObjectID) }
        return (Self.jsonString(["ok": true, "editedPulse": number, "changed": changed]), "Edited pulse \(number)")
    }

    @MainActor
    private func deletePulse(taskID: NSManagedObjectID, number: Int, goalObjectID: NSManagedObjectID?) -> (String, String?) {
        let ctx = PersistenceController.shared.container.viewContext
        guard let task = try? ctx.existingObject(with: taskID) as? DailyTask else {
            return (Self.errJSON("Pulse not found."), nil)
        }
        let title = task.title ?? "pulse"
        ctx.delete(task)
        try? ctx.save()
        WidgetDataService.shared.updateWidgets(context: ctx)
        if let goalObjectID { fireGoalSync(goalObjectID) }
        return (Self.jsonString(["ok": true, "deletedPulse": number, "title": title]), "Deleted pulse \(number)")
    }

    @MainActor
    private func completePulse(taskID: NSManagedObjectID, number: Int, goalObjectID: NSManagedObjectID?) -> (String, String?) {
        let ctx = PersistenceController.shared.container.viewContext
        guard let task = try? ctx.existingObject(with: taskID) as? DailyTask else {
            return (Self.errJSON("Pulse not found."), nil)
        }
        guard !task.isCompleted else {
            return (Self.jsonString(["ok": true, "alreadyComplete": number]), nil)
        }
        task.isCompleted = true
        task.completedDate = Date()
        task.verificationStatus = "verified"
        // Finish the goal + stop its reminders if this completed the last step,
        // so the daily "log it" check-in stops firing for a finished goal.
        let goalForCompletion = task.goal ?? (goalObjectID.flatMap { try? ctx.existingObject(with: $0) as? Goal })
        let completedGoalID = goalForCompletion?.id?.uuidString ?? ""
        let justCompleted = goalForCompletion?.markCompletedIfAllStepsDone() ?? false
        // Credit XP / level / streak identically to in-app completions. This is a
        // background (chat-driven) path, so go straight through the canonical
        // helper — no celebration overlay. registerCompletion saves the context
        // and refreshes the widget after awarding the XP.
        let profile = UserProfile.fetchOrCreate(in: ctx)
        profile.registerCompletion(xp: Int(task.xpReward), in: ctx)
        if justCompleted {
            AdaptiveNotificationScheduler.handleGoalCompletion(goalID: completedGoalID)
        }
        WidgetDataService.shared.updateWidgets(context: ctx)
        if let goalObjectID { fireGoalSync(goalObjectID) }
        return (Self.jsonString(["ok": true, "completedPulse": number]), "Marked pulse \(number) done")
    }

    @MainActor
    private func changeGoal(goalID: NSManagedObjectID, args: [String: Any]) -> (String, String?) {
        let ctx = PersistenceController.shared.container.viewContext
        guard let goal = try? ctx.existingObject(with: goalID) as? Goal else {
            return (Self.errJSON("Goal not found."), nil)
        }
        var changed: [String] = []
        if let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            goal.title = title; changed.append("title")
        }
        if let desc = args["description"] as? String, !desc.isEmpty {
            goal.goalDescription = desc; changed.append("description")
        }
        if let days = Self.intArg(args, "deadlineDays"), days > 0 {
            goal.deadline = Calendar.current.date(byAdding: .day, value: days, to: Date())
            changed.append("deadline")
        }
        if let m = Self.intArg(args, "motivation") {
            goal.motivationLevel = Int16(clamping: max(1, min(10, m)))
            changed.append("motivation")
        }
        guard !changed.isEmpty else { return (Self.errJSON("No fields to change were provided."), nil) }
        try? ctx.save()
        WidgetDataService.shared.updateWidgets(context: ctx)
        fireGoalSync(goalID)
        return (Self.jsonString(["ok": true, "changed": changed]), "Updated the goal (\(changed.joined(separator: ", ")))")
    }

    // MARK: - Read helpers (main-actor)

    @MainActor
    private func orderedPulseIDs(_ goalObjectID: NSManagedObjectID?) -> [NSManagedObjectID] {
        guard let goalID = goalObjectID,
              let goal = try? PersistenceController.shared.container.viewContext.existingObject(with: goalID) as? Goal
        else { return [] }
        return goal.dailyTasksArray.map { $0.objectID }
    }

    @MainActor
    private func pulseCount(goalID: NSManagedObjectID) -> Int {
        guard let goal = try? PersistenceController.shared.container.viewContext.existingObject(with: goalID) as? Goal
        else { return 0 }
        return goal.dailyTasksArray.count
    }

    @MainActor
    private func goalStateJSON(goalObjectID: NSManagedObjectID?) -> String {
        guard let goalID = goalObjectID,
              let goal = try? PersistenceController.shared.container.viewContext.existingObject(with: goalID) as? Goal
        else { return Self.errJSON("No goal selected.") }

        let pulses: [[String: Any]] = goal.dailyTasksArray.enumerated().map { (i, t) in
            [
                "number": i + 1,
                "title": t.title ?? "Untitled",
                "completed": t.isCompleted,
                "estimatedMinutes": Int(t.estimatedMinutes),
                "proofType": t.proofType ?? "text"
            ]
        }
        let done = goal.dailyTasksArray.filter { $0.isCompleted }.count
        let state: [String: Any] = [
            "ok": true,
            "goalTitle": goal.titleValue,
            "category": goal.categoryEnum.displayName,
            "daysRemaining": goal.daysRemaining,
            "motivation": Int(goal.motivationLevel),
            "completedCount": done,
            "totalPulses": goal.dailyTasksArray.count,
            "pulses": pulses
        ]
        return Self.jsonString(state)
    }

    // MARK: - Firestore sync (mirror AIPulseGenerator's fire-and-forget pattern)

    private func fireGoalSync(_ objectID: NSManagedObjectID) {
        Task.detached(priority: .utility) {
            await MainActor.run {
                let ctx = PersistenceController.shared.container.viewContext
                if let goal = try? ctx.existingObject(with: objectID) as? Goal {
                    Task.detached { try? await FirestoreSyncService.shared.syncGoal(goal) }
                }
            }
        }
    }

    // MARK: - Number resolution

    /// Resolve a `pulse_number` arg against the pre-round snapshot of pulse IDs.
    private func pulseID(from args: [String: Any], roundPulseIDs: [NSManagedObjectID]) -> (objectID: NSManagedObjectID, number: Int)? {
        guard let n = Self.intArg(args, "pulse_number"), n >= 1, n <= roundPulseIDs.count else { return nil }
        return (roundPulseIDs[n - 1], n)
    }

    // MARK: - Static utilities

    private static func parseArgs(_ s: String) -> [String: Any] {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private static func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        if let s = args[key] as? String, let i = Int(s) { return i }
        return nil
    }

    private static func normalizedProofType(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "photo": return "photo"
        case "number": return "number"
        default: return "text"
        }
    }

    private static func jsonString(_ obj: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    private static func errJSON(_ msg: String) -> String {
        jsonString(["ok": false, "error": msg])
    }

    /// Build a clean assistant message to re-append into the conversation. The raw
    /// message may carry `content: null` alongside tool_calls; OpenAI-compatible
    /// APIs want a present (possibly empty) content string plus the tool_calls.
    private static func normalizedAssistantMessage(_ raw: [String: Any]) -> [String: Any] {
        var msg: [String: Any] = ["role": "assistant"]
        if let content = raw["content"] as? String {
            msg["content"] = content
        } else {
            msg["content"] = ""
        }
        if let toolCalls = raw["tool_calls"] {
            msg["tool_calls"] = toolCalls
        }
        return msg
    }

    private static func emptyReplyFallback(didMutate: Bool) -> String {
        didMutate
            ? "Done — I've updated your plan."
            : "I'm here. What do you want to work on?"
    }

    private static func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "overdue"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days)d"
        }
    }
}
