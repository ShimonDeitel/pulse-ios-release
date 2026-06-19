import SwiftUI
import CoreData

/// Detail screen specifically for Transformation goals — replaces the generic
/// GoalDetailView routing when the goal's category == "transformation".
///
/// Shows:
///   • Hero card (current → goal photos, weeks remaining, body-fat targets)
///   • Big primary CTA: "Start Workout for Today"
///   • Secondary CTA: "Meal Details for Today"
///   • Inline AI Q&A
struct TransformationDetailView: View {
    @ObservedObject var goal: Goal
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @State private var plan: TransformationPlan?
    @State private var showingWorkoutSheet = false
    @State private var showingMealSheet = false
    @State private var showingAdjust = false
    @State private var showingChat = false
    @State private var askText = ""
    @State private var askAnswer = ""
    @State private var asking = false

    private var todayWorkout: DailyWorkout? {
        guard let workouts = plan?.workouts, !workouts.isEmpty else { return nil }
        let cycleOffset = dayOffsetToday() % workouts.count
        return workouts.first(where: { $0.dayOffset == cycleOffset })
            ?? workouts.first
    }

    /// True once today's workout has been marked complete. Mirrors how the
    /// Mark-Complete action tags the matching DailyTask (stepNumber == dayOffset+1,
    /// see markWorkoutComplete) so the CTA can flip to "Today's Workout Complete"
    /// + green. Recomputed when the workout sheet dismisses, so closing the sheet
    /// after marking everything done updates the button.
    private var todayIsComplete: Bool {
        guard let w = todayWorkout, w.isRestDay == false else { return false }
        let target = Int16(clamping: w.dayOffset + 1)
        return (goal.dailyTasks as? Set<DailyTask>)?
            .contains { $0.stepNumber == target && $0.isCompleted } ?? false
    }

    private var weeksRemaining: Int {
        max(0, (goal.daysRemaining + 6) / 7)
    }

    var body: some View {
        // Buttons flow at the END of the scroll content — NOT pinned to
        // the screen edge. The user only reaches Start Workout + Meal
        // Details once they've scrolled past the hero, calendar, and
        // ask card. No more sticky bar covering content.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                WorkoutCalendar(goal: goal)
                askCard
                bottomActionBar
                    .padding(.top, 12)
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .pulseScreen()
        .navigationTitle(goal.titleValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(PulseColors.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingChat = true } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .foregroundColor(PulseColors.ink)
                }
                .accessibilityLabel("Chat about this goal")
            }
            if plan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdjust = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(PulseColors.ink)
                    }
                }
            }
        }
        .task {
            loadPlan()
        }
        .sheet(isPresented: $showingWorkoutSheet) {
            if let workout = todayWorkout, let plan = plan {
                TodayWorkoutSheet(workout: workout, plan: plan, goal: goal)
                    .environment(\.managedObjectContext, viewContext)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $showingMealSheet) {
            if let plan = plan {
                MealDetailsSheet(plan: plan)
            }
        }
        .sheet(isPresented: $showingAdjust) {
            if let plan = plan {
                AdjustTransformationSheet(goal: goal, plan: plan) {
                    loadPlan()   // refresh after a rebuild
                }
                .environment(\.managedObjectContext, viewContext)
            }
        }
        .sheet(isPresented: $showingChat) {
            NavigationStack { MentorChatView(fixedGoal: goal) }
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 0) {
            // Status banner — single line, scales down if needed
            HStack(spacing: 8) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("WEEK \(currentWeek()) OF \(plan?.estimatedWeeks ?? weeksRemaining)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(weeksRemaining)W LEFT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(PulseColors.signal)

            // Photos row (current → goal)
            photoStrip
                .padding(.horizontal, 16)
                .padding(.top, 14)

            // Stats row
            HStack(spacing: 0) {
                heroStat(label: "BODY FAT", value: plan.map { "~\($0.currentBodyFatPct)%" } ?? "—")
                divider
                heroStat(label: "TARGET", value: plan.map { "~\($0.goalBodyFatPct)%" } ?? "—")
                divider
                heroStat(label: "DONE", value: "\(doneCount)/\(totalCount)")
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)

            // Assessment — the AI's written read on the user. It can run long, so
            // give it generous line spacing + leading alignment for an easy read,
            // and fixedSize(vertical) so the whole paragraph shows (never clipped).
            if let assessment = plan?.assessment, !assessment.isEmpty {
                Text(assessment)
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.muted)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var doneCount: Int {
        (goal.dailyTasks as? Set<DailyTask>)?.filter { $0.isCompleted }.count ?? 0
    }
    private var totalCount: Int {
        (goal.dailyTasks as? Set<DailyTask>)?.count ?? 0
    }

    private var photoStrip: some View {
        HStack(spacing: 10) {
            transformationPhoto(forKey: "transformation_current_\(goal.id?.uuidString ?? "")", label: "NOW")
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PulseColors.signal)
            transformationPhoto(forKey: "transformation_goal_\(goal.id?.uuidString ?? "")", label: "GOAL")
        }
    }

    private func transformationPhoto(forKey key: String, label: String) -> some View {
        let data = UserDefaults.standard.data(forKey: key)
        let image = data.flatMap { UIImage(data: $0) }
        return VStack(spacing: 4) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PulseColors.surfaceContainer)
                    .frame(height: 130)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundColor(PulseColors.muted)
                    )
            }
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(PulseColors.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(PulseColors.hair)
            .frame(width: 1, height: 28)
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(PulseColors.ink)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(PulseColors.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PulseColors.ink)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(PulseColors.muted)
        }
    }

    // MARK: - Ask card

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ASK YOUR COACH")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.signal)

            HStack(spacing: 8) {
                TextField("e.g. swap squats for lunges?", text: $askText, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundColor(PulseColors.ink)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button {
                    Task { await ask() }
                } label: {
                    Image(systemName: asking ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(askText.isEmpty || asking ? PulseColors.muted : PulseColors.signal)
                }
                .disabled(askText.isEmpty || asking)
            }

            if !askAnswer.isEmpty {
                Text(askAnswer)
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.ink)
                    .lineSpacing(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseColors.signal.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Bottom action bar (sticky)

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            // PRIMARY: Start Workout for Today
            Button {
                showingWorkoutSheet = true
                PulseHaptics.medium()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: todayWorkout?.isRestDay == true ? "leaf.fill" : (todayIsComplete ? "checkmark.circle.fill" : "play.fill"))
                        .font(.system(size: 14, weight: .bold))
                    Text(todayWorkout?.isRestDay == true ? "Today is a Rest Day" : (todayIsComplete ? "Today's Workout Complete" : "Start Workout for Today"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                // Green once today's session is marked done; brand red otherwise.
                .background(todayIsComplete ? PulseColors.green : PulseColors.signal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // SECONDARY: Meal Details
            Button {
                showingMealSheet = true
                PulseHaptics.light()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Meal Details for Today")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(PulseColors.signal)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(PulseColors.signal.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PulseColors.signal.opacity(0.35), lineWidth: 1)
                )
            }
        }
        // Inline at the end of the scroll content — no sticky background.
    }

    // MARK: - Logic

    /// Hydrate `plan` for the workout + meal sheets.
    ///
    /// Priority order:
    ///   1. Decode the AI-generated `aiRoadmapJSON` if present (vision flow succeeded).
    ///   2. Otherwise synthesize a TransformationPlan from the goal's DailyTasks
    ///      + sensible defaults. This is what powers Start Workout and Meal
    ///      Details when the goal was created via the non-AI fallback path.
    ///
    /// Without (2), both sheets render as empty gray rectangles because their
    /// `if let plan = plan` guards fail.
    private func loadPlan() {
        if let json = goal.aiRoadmapJSON,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(TransformationPlan.self, from: data) {
            plan = decoded
            return
        }
        plan = synthesizePlanFromTasks()
    }

    private func synthesizePlanFromTasks() -> TransformationPlan {
        let tasks = (goal.dailyTasks as? Set<DailyTask> ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }

        // Default macros — calibrated for a 165 lb adult at a small cut.
        // Real numbers when the AI plan is available; this is just so the
        // meal sheet always renders something useful.
        let macros = DailyMacros(
            calories: 2200,
            proteinGrams: 165,
            carbsGrams: 220,
            fatGrams: 75
        )

        // Convert each DailyTask into a DailyWorkout. Parse the structured
        // EXERCISES: block out of the fallback howTo text so each move
        // (push-ups, dips, plank-to-push-up, …) becomes its OWN row in the
        // workout sheet — each with its own Live + Example buttons.
        let workouts: [DailyWorkout] = tasks.enumerated().map { _, task in
            let title = task.title ?? "Workout"
            let howTo = task.howToDescription ?? task.taskDescription ?? "Do today's session."
            let isRest = title.lowercased().contains("rest") || title.lowercased().contains("recovery")

            let exercises: [WorkoutExercise]
            if isRest {
                exercises = [WorkoutExercise(
                    name: "Active recovery",
                    sets: 1,
                    reps: "See notes",
                    restSeconds: 0,
                    notes: howTo
                )]
            } else {
                let parsed = Self.parseExercisesFromHowTo(howTo)
                exercises = parsed.isEmpty
                    ? [WorkoutExercise(name: "Today's session", sets: 1, reps: "See notes", restSeconds: 0, notes: howTo)]
                    : parsed
            }

            return DailyWorkout(
                dayOffset: Int(task.sortOrder),
                title: title,
                focus: focusLabel(for: title),
                estimatedMinutes: Int(task.estimatedMinutes),
                exercises: exercises,
                isRestDay: isRest
            )
        }

        return TransformationPlan(
            assessment: goal.goalDescription ?? "Stay consistent with the daily sessions. Track effort and recover well.",
            estimatedWeeks: max(1, (goal.daysRemaining + 6) / 7),
            currentBodyFatPct: 20,
            goalBodyFatPct: 15,
            dailyMacros: macros,
            mealsGuidance: """
            Eat 3-4 meals a day, each anchored on a palm-sized protein source (chicken, fish, eggs, Greek yogurt, tofu, lentils). Fill half your plate with vegetables, the rest with rice / potatoes / fruit. Drink 2-3 L of water. Limit liquid calories — soda, juice, alcohol are the biggest stealth killers of a transformation.
            """,
            workouts: workouts,
            weeklyMilestones: [
                "Week 1: every planned session completed",
                "Week 2: small but visible progress in baseline numbers",
                "Week 4: noticeable energy + sleep improvement"
            ],
            habits: [
                "Take a body photo every Sunday in the same lighting",
                "Sleep 7+ hours — non-negotiable",
                "Hit your protein target every day"
            ],
            trainingStyle: "auto",
            weight: 0,
            weightUnit: "lb"
        )
    }

    /// Parse the fallback howTo text into individual WorkoutExercise rows.
    ///
    /// The fallback howTo template looks like:
    ///   FOCUS: ...
    ///
    ///   EXERCISES:
    ///   1. Bench press 4×8
    ///   2. Overhead press 3×8
    ///   3. Pike push-ups 3×8
    ///   ...
    ///
    ///   Warm up 5 min. Cool down 5 min. ...
    ///
    /// We pull out each numbered line and split "Name SxR" → name + sets + reps.
    /// Reps default to "max" if not present (e.g. "Pull-ups 5×max").
    static func parseExercisesFromHowTo(_ text: String) -> [WorkoutExercise] {
        // Find the EXERCISES: block
        let lower = text.lowercased()
        guard let exRange = lower.range(of: "exercises:") else { return [] }
        let after = text[exRange.upperBound...]
        // Stop at a blank line followed by non-numbered content (the "Warm up..." trailer)
        let lines = after.split(separator: "\n", omittingEmptySubsequences: false)

        var out: [WorkoutExercise] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !out.isEmpty { break }   // blank line after exercises = end
                continue
            }
            // Numbered prefix like "1. " or "1) "
            let stripped: String
            if let dotIdx = line.firstIndex(of: ".") ?? line.firstIndex(of: ")"),
               let firstChar = line.first, firstChar.isNumber {
                stripped = String(line[line.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
            } else if let first = line.first, first.isNumber {
                stripped = line
            } else {
                // Not a numbered exercise line — assume we've left the list.
                if !out.isEmpty { break }
                continue
            }
            guard let ex = parseSingleExercise(stripped) else { continue }
            out.append(ex)
        }
        return out
    }

    /// Parse one line like "Bench press 4×8" or "Pull-ups 5×max" or
    /// "Plank 3×60s" or "5 rounds: 10 burpees, 10 KB swings".
    private static func parseSingleExercise(_ line: String) -> WorkoutExercise? {
        // Try "name SETS×REPS" with × or x
        let separators: [Character] = ["×", "x", "X"]
        for sep in separators {
            // Find LAST occurrence so multi-word names work ("Romanian deadlift 3×8")
            if let sepIdx = line.lastIndex(of: sep) {
                guard sepIdx > line.startIndex else { continue }
                // Walk back to the start of the digits before sep
                var i = line.index(before: sepIdx)
                while i > line.startIndex, line[i].isWhitespace { i = line.index(before: i) }
                var setsEnd = i
                while i > line.startIndex, line[i].isNumber { i = line.index(before: i) }
                if !line[i].isNumber { i = line.index(after: i) }
                guard i <= setsEnd else { continue }
                let setsStr = String(line[i...setsEnd])
                guard let sets = Int(setsStr) else { continue }

                // Name is everything before the sets number (trimmed)
                let name = String(line[..<i]).trimmingCharacters(in: .whitespaces)
                // Reps is everything after sep
                let repsRaw = String(line[line.index(after: sepIdx)...]).trimmingCharacters(in: .whitespaces)
                // Trim trailing punctuation
                let reps = repsRaw.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))

                if !name.isEmpty && !reps.isEmpty {
                    return WorkoutExercise(
                        name: name,
                        sets: sets,
                        reps: reps,
                        restSeconds: 60,
                        notes: nil
                    )
                }
            }
        }
        // Fallback: treat the whole line as a single exercise with 1 set, "see notes"
        if !line.isEmpty {
            return WorkoutExercise(name: line, sets: 1, reps: "as written", restSeconds: 0, notes: nil)
        }
        return nil
    }

    /// Derive a one-line focus label from the workout title. Falls back to "Training day".
    private func focusLabel(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("push")     { return "Push — chest, shoulders, triceps" }
        if lower.contains("pull")     { return "Pull — back, biceps" }
        if lower.contains("leg")      { return "Legs — quads, hamstrings, glutes" }
        if lower.contains("upper")    { return "Upper body" }
        if lower.contains("lower")    { return "Lower body" }
        if lower.contains("cardio")   { return "Cardio" }
        if lower.contains("recovery") || lower.contains("rest") { return "Active recovery" }
        if lower.contains("strength") { return "Strength" }
        if lower.contains("circuit") || lower.contains("conditioning") { return "Conditioning" }
        if lower.contains("test")     { return "Benchmark / test" }
        return "Training day"
    }

    private func dayOffsetToday() -> Int {
        guard let created = goal.createdAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: created),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return max(0, days)
    }

    private func currentWeek() -> Int {
        max(1, dayOffsetToday() / 7 + 1)
    }

    private func ask() async {
        guard let plan = plan, !askText.isEmpty else { return }
        asking = true
        defer { asking = false }
        do {
            askAnswer = try await PhotoTransformationService.shared.askAboutPlan(question: askText, plan: plan)
            askText = ""
        } catch {
            askAnswer = "Couldn't get an answer right now. Try again in a moment."
        }
    }
}

// MARK: - Today Workout Sheet

struct TodayWorkoutSheet: View {
    let workout: DailyWorkout
    let plan: TransformationPlan
    let goal: Goal
    /// When true, the Swap sheet pulls same-muscle alternatives from the
    /// on-device library (no AI) — set by the free Custom Workout detail.
    var useLibrary: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @State private var completedSet: Set<String> = []
    @State private var liveExercise: WorkoutExercise?

    // Mutable copy of the exercises so the user can SWAP any of them for an
    // alternative that hits the same muscle group with equipment they have.
    @State private var exercises: [WorkoutExercise] = []
    @State private var swapping: WorkoutExercise?   // exercise being swapped
    @State private var editingExercise: WorkoutExercise?  // exercise being edited
    /// Whether today's DailyTask was already complete when this sheet opened —
    /// so we celebrate only on a fresh completion, not every time you reopen a
    /// finished day.
    @State private var wasCompleteOnOpen = false

    /// Per-day key so exercises you ticked off stay ticked when you reopen today's
    /// workout (completedSet is otherwise ephemeral @State).
    private var completionKey: String {
        "pulse_workout_done_\(goal.id?.uuidString ?? "x")_\(workout.dayOffset)"
    }

    /// Whether EVERY current exercise is ticked off. Drives the action button's
    /// green "Marked as Complete" state. Because it's derived from the LIVE
    /// exercise list, adding a new exercise after a previous completion flips it
    /// back to actionable — so tapping Mark Complete re-ticks the new one too.
    private var allMarked: Bool {
        !exercises.isEmpty && exercises.allSatisfy { completedSet.contains($0.id) }
    }

    /// How many exercises are ticked off so far — drives the finish button's
    /// "X of N done" progress label while the day is still incomplete.
    private var doneCount: Int {
        exercises.filter { completedSet.contains($0.id) }.count
    }

    /// Whether today's DailyTask is currently marked complete (the source of
    /// truth the detail screen reads). For a workout day this stays in lockstep
    /// with `allMarked` via syncDayCompletion; rest days are driven by the button.
    private var dayTaskComplete: Bool {
        let target = Int16(clamping: workout.dayOffset + 1)
        return (goal.dailyTasks as? Set<DailyTask>)?
            .contains { $0.stepNumber == target && $0.isCompleted } ?? false
    }

    /// The day is "complete" (green) when every exercise is ticked — or, for a
    /// rest day, when its task is marked done.
    private var isDayComplete: Bool {
        workout.isRestDay ? dayTaskComplete : allMarked
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.focus.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(PulseColors.signal)
                        Text(workout.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(PulseColors.ink)
                        HStack(spacing: 12) {
                            // Live: recomputed from the editable `exercises` array
                            // so editing reps/rounds/rest or swapping updates the
                            // duration instantly (falls back to the saved set
                            // before the first load).
                            let live = exercises.isEmpty ? workout.exercises : exercises
                            Label("\(pulseWorkoutMinutes(live)) min", systemImage: "clock")
                            Label("\(live.count) exercises", systemImage: "list.bullet")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.muted)
                    }

                    if workout.isRestDay {
                        VStack(spacing: 8) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 36))
                                .foregroundColor(PulseColors.signal)
                            Text("Rest is part of the plan.")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(PulseColors.ink)
                            Text("Stretch, hydrate, sleep well.")
                                .font(.system(size: 13))
                                .foregroundColor(PulseColors.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(PulseColors.signal.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                            exerciseRow(index: idx + 1, exercise: ex)
                        }
                    }

                    // STATUS — not a finish-all shortcut. It reflects the day's state
                    // and NEVER dismisses the sheet: you complete the day by ticking
                    // each exercise above (each turns green), and you leave via Done
                    // (top-right) when you're ready. Green once every exercise is
                    // checked; red while any remain — uncheck one and it flips back.
                    // A rest day has nothing to tick, so its button toggles directly.
                    Button {
                        if workout.isRestDay {
                            setDayCompleted(!dayTaskComplete)
                            PulseHaptics.success()
                        }
                        // non-rest: no-op — completion is driven by the per-exercise ticks.
                    } label: {
                        HStack(spacing: 8) {
                            if isDayComplete {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(workout.isRestDay
                                 ? (dayTaskComplete ? "Day Complete" : "Mark Day Complete")
                                 : (allMarked ? "Workout Complete"
                                    : "\(doneCount) of \(exercises.count) done — check off the rest"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isDayComplete ? PulseColors.green : PulseColors.signal)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .animation(.snappy(duration: 0.28), value: isDayComplete)
                    }
                    // Non-rest button is a pure status indicator (no tap action);
                    // the rest-day button stays tappable to toggle completion.
                    .allowsHitTesting(workout.isRestDay)
                    .padding(.top, 12)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.vertical, 16)
            }
            .pulseScreen()
            .navigationTitle("Today's Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { closeSheet() }
                }
            }
            // Seed the mutable exercise list from the plan on first appear.
            .onAppear {
                if exercises.isEmpty { exercises = workout.exercises }
                // Remember whether today was ALREADY done on open, so we only
                // celebrate a fresh completion (not every reopen of a finished day).
                wasCompleteOnOpen = dayTaskComplete
                // Restore which exercises were ticked off for today so they stay
                // marked when you reopen the workout.
                if let saved = UserDefaults.standard.array(forKey: completionKey) as? [String] {
                    completedSet = Set(saved)
                }
            }
            .onChange(of: completedSet) { _, newValue in
                UserDefaults.standard.set(Array(newValue), forKey: completionKey)
                // Keep the day's completion in lockstep with the checkmarks — BOTH
                // ways. All ticked → day done (green everywhere); uncheck any → back
                // to incomplete (red). Never dismisses — you close via Done.
                syncDayCompletion()
            }
        }
        // Full-screen Live Mode for the tapped exercise.
        // When Live completes, mark the exercise done in completedSet and
        // auto-finish the whole workout if every exercise is now done.
        .fullScreenCover(item: $liveExercise) { ex in
            LiveWorkoutView(exercise: ex) { completedExerciseID in
                // Ticks this exercise — the same onChange → syncDayCompletion as a
                // manual tick, so the day turns green once Live finishes the last
                // one. No dismiss: you land back on the workout and can review it.
                completedSet.insert(completedExerciseID)
                PulseHaptics.success()
            }
        }
        // Swap sheet — pick a same-muscle-group alternative.
        .sheet(item: $swapping) { ex in
            SwapExerciseSheet(
                original: ex,
                trainingStyle: plan.trainingStyle,
                useLibrary: useLibrary
            ) { replacement in
                if let i = exercises.firstIndex(where: { $0.id == ex.id }) {
                    // Carry the original's sets/reps/rest onto the replacement so a
                    // swap changes only the MOVE, not your prescribed volume.
                    let merged = WorkoutExercise(
                        name: replacement.name,
                        sets: ex.sets,
                        reps: ex.reps,
                        restSeconds: ex.restSeconds,
                        notes: replacement.notes
                    )
                    exercises[i] = merged
                    // completedSet keys on the computed id (name-sets-reps), so a
                    // swap would otherwise un-tick a finished move. Carry the tick
                    // across to the replacement's new id.
                    if completedSet.remove(ex.id) != nil {
                        completedSet.insert(merged.id)
                    }
                    persistExerciseEdits()
                }
                swapping = nil
                PulseHaptics.success()
            }
        }
        // Edit sheet — set your own rep target / sets.
        .sheet(item: $editingExercise) { ex in
            EditExerciseSheet(exercise: ex) { updated in
                if let i = exercises.firstIndex(where: { $0.id == ex.id }) {
                    exercises[i] = updated
                    // Editing sets/reps changes the computed id, which would drop an
                    // existing tick — carry it across to the updated exercise's id.
                    if completedSet.remove(ex.id) != nil {
                        completedSet.insert(updated.id)
                    }
                    persistExerciseEdits()
                }
                editingExercise = nil
                PulseHaptics.success()
            }
        }
    }

    /// Remove an exercise from today's workout entirely.
    private func deleteExercise(_ exercise: WorkoutExercise) {
        exercises.removeAll { $0.id == exercise.id }
        completedSet.remove(exercise.id)
        persistExerciseEdits()
        PulseHaptics.warning()
    }

    /// Write the live `exercises` array back into the goal's saved plan so Swap /
    /// Edit / Delete survive reopening the sheet. Rebuilds only THIS day's
    /// DailyWorkout inside the decoded TransformationPlan (preserving every other
    /// day + field), re-encodes to `goal.aiRoadmapJSON`, and saves.
    ///
    /// No-ops when there's no decodable roadmap JSON (the synthesized-from-tasks
    /// fallback path) — there's nothing to write back, and the in-memory list still
    /// drives the current session, matching prior behaviour.
    private func persistExerciseEdits() {
        guard let json = goal.aiRoadmapJSON,
              let data = json.data(using: .utf8),
              let current = try? JSONDecoder().decode(TransformationPlan.self, from: data) else { return }

        let rebuiltDay = DailyWorkout(
            dayOffset: workout.dayOffset,
            title: workout.title,
            focus: workout.focus,
            estimatedMinutes: workout.isRestDay ? workout.estimatedMinutes : pulseWorkoutMinutes(exercises),
            exercises: exercises,
            isRestDay: workout.isRestDay
        )
        let newWorkouts = current.workouts.map { $0.dayOffset == workout.dayOffset ? rebuiltDay : $0 }

        // TransformationPlan.workouts is `let`, so rebuild the struct preserving
        // every other field (plus the stable id + manual flag).
        var newPlan = TransformationPlan(
            assessment: current.assessment,
            estimatedWeeks: current.estimatedWeeks,
            currentBodyFatPct: current.currentBodyFatPct,
            goalBodyFatPct: current.goalBodyFatPct,
            dailyMacros: current.dailyMacros,
            mealsGuidance: current.mealsGuidance,
            workouts: newWorkouts,
            weeklyMilestones: current.weeklyMilestones,
            habits: current.habits,
            trainingStyle: current.trainingStyle,
            weight: current.weight,
            weightUnit: current.weightUnit
        )
        newPlan.id = current.id
        newPlan.isManual = current.isManual

        if let encoded = try? JSONEncoder().encode(newPlan),
           let s = String(data: encoded, encoding: .utf8) {
            goal.aiRoadmapJSON = s
            try? viewContext.save()
        }
    }

    private func exerciseRow(index: Int, exercise: WorkoutExercise) -> some View {
        let done = completedSet.contains(exercise.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if done { completedSet.remove(exercise.id) }
                else    { completedSet.insert(exercise.id); PulseHaptics.light() }
            } label: {
                ZStack {
                    // Fills GREEN once this exercise is ticked off, so each one
                    // visibly turns green — the day only completes when ALL are green.
                    Circle()
                        .fill(done ? PulseColors.green : Color.clear)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(done ? PulseColors.green : PulseColors.muted, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(PulseColors.muted)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(done ? PulseColors.muted : PulseColors.ink)
                    .strikethrough(done)
                HStack(spacing: 10) {
                    Text("\(exercise.sets) × \(exercise.reps)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(PulseColors.signal)
                    Text("rest \(exercise.restSeconds)s")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PulseColors.muted)
                }
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ── Live + Example + Swap buttons (one line, no wrap) ───
                HStack(spacing: 6) {
                    Button {
                        liveExercise = exercise
                        PulseHaptics.medium()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Live")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PulseColors.signal)
                        .clipShape(Capsule())
                    }

                    Button {
                        openYouTube(query: "\(exercise.name) proper form")
                        PulseHaptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Example")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(PulseColors.signal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PulseColors.signal.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(PulseColors.signal.opacity(0.35), lineWidth: 1))
                    }

                    Button {
                        swapping = exercise
                        PulseHaptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Swap")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(PulseColors.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(PulseColors.hair, lineWidth: 1))
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 4)

            // 3-line menu — Edit reps/sets or Delete this exercise.
            Menu {
                Button { editingExercise = exercise } label: {
                    Label("Edit reps & sets", systemImage: "pencil")
                }
                Button(role: .destructive) { deleteExercise(exercise) } label: {
                    Label("Delete exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(PulseColors.muted)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Leaving the sheet (the Done button). Persists the final completion state
    /// (already mirrored to the checkmarks), then celebrates ONCE — only for a day
    /// that became complete during THIS session — on the way out, so the
    /// celebration shows on the detail screen rather than hidden behind this sheet.
    private func closeSheet() {
        // syncDayCompletion → setDayCompleted already performed the canonical XP /
        // level / streak / save / widget mutation for this completion. So here we
        // ONLY raise the celebration overlay (setting celebrationData directly), and
        // must NOT call celebratePulseCompletion — that would award the XP a 2nd time.
        syncDayCompletion()
        if isDayComplete, !wasCompleteOnOpen {
            let target = Int16(clamping: workout.dayOffset + 1)
            if let task = (goal.dailyTasks as? Set<DailyTask>)?.first(where: { $0.stepNumber == target }) {
                let profile = UserProfile.fetchOrCreate(in: viewContext)
                appState.celebrationData = PulseCelebrationData(
                    pulseNumber: Int(task.stepNumber),
                    xpGained: Int(task.xpReward),
                    totalXP: Int(profile.totalXP),
                    nextPulseTitle: nil,
                    didLevelUp: false,
                    newLevel: profile.levelValue,
                    goalTitle: goal.titleValue,
                    authorId: AuthManager.shared.currentUser?.userId ?? profile.id?.uuidString ?? "me",
                    authorName: profile.displayNameValue.isEmpty ? "You" : profile.displayNameValue
                )
            }
        }
        dismiss()
    }

    /// Drive the day's completion straight from the checkmarks — every exercise
    /// ticked → complete; any unticked → incomplete (so the detail screen flips
    /// green → red). Rest days are handled by their button. Never dismisses.
    private func syncDayCompletion() {
        guard !workout.isRestDay else { return }
        setDayCompleted(allMarked)
    }

    /// Set today's DailyTask completion to `complete` (idempotent) + persist.
    /// Works BOTH ways, so unchecking an exercise reverts the day to incomplete.
    /// No dismiss and no celebration — closeSheet handles the celebration.
    ///
    /// Delegates the actual mutation to the shared `DailyTask.setCompletion` so
    /// this sheet and the calendar's Day Detail credit XP / progress / goal status
    /// through the exact same guarded, single-award path.
    private func setDayCompleted(_ complete: Bool) {
        let req: NSFetchRequest<DailyTask> = DailyTask.fetchRequest()
        req.predicate = NSPredicate(format: "goal == %@ AND stepNumber == %d", goal, Int16(clamping: workout.dayOffset + 1))
        req.fetchLimit = 1
        guard let task = (try? viewContext.fetch(req))?.first else { return }
        task.setCompletion(complete, in: viewContext)
    }
}

// MARK: - Swap Exercise Sheet
//
// Lists alternatives for an exercise the user can't / doesn't want to do.
// Every alternative targets the SAME primary muscle group and is filtered to
// the user's equipment tier — so swapping a "Barbell bench press" for someone
// with no gym shows "Push-ups", "Diamond push-ups", "Decline push-ups", etc.,
// never another barbell move. Picking one replaces it in the workout.
struct SwapExerciseSheet: View {
    let original: WorkoutExercise
    let trainingStyle: String
    /// When true, alternatives come from the on-device WorkoutLibrary (no AI) —
    /// used by the free Custom Workout flow. When false, they're AI-generated.
    var useLibrary: Bool = false
    let onPick: (WorkoutExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var allAlternatives: [WorkoutExercise] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// Client-side filter over the AI-returned alternatives.
    private var filtered: [WorkoutExercise] {
        guard !searchText.isEmpty else { return allAlternatives }
        return allAlternatives.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if isLoading {
                        loadingState
                    } else if let err = errorMessage {
                        errorState(err)
                    } else if filtered.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 8) {
                            ForEach(filtered) { alt in
                                altRow(alt)
                            }
                        }
                        .padding(.horizontal, PulseSpacing.screenEdge)
                    }
                    Spacer(minLength: 30)
                }
            }
            .pulseScreen()
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search alternatives")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .task { await load() }
        }
    }

    // MARK: - States

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SWAPPING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.muted)
            Text(original.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(PulseColors.ink)
            Text(useLibrary
                 ? "Alternatives that train the same muscle group."
                 : "AI-picked alternatives that train the same muscles with your equipment.")
                .font(.system(size: 13))
                .foregroundColor(PulseColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 4)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PulseColors.signal)
            Text("Finding alternatives…")
                .font(.system(size: 13))
                .foregroundColor(PulseColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(PulseColors.muted)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(PulseColors.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await load() }
            } label: {
                Text("Try Again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(PulseColors.signal)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        Text(searchText.isEmpty
             ? "No alternatives came back. Tap Cancel and try again."
             : "No alternatives matched “\(searchText)”.")
            .font(.system(size: 13))
            .foregroundColor(PulseColors.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.top, 24)
    }

    private func altRow(_ alt: WorkoutExercise) -> some View {
        HStack(spacing: 10) {
            // Tap the main area to swap to this exercise.
            Button {
                onPick(alt)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 18))
                        .foregroundColor(PulseColors.signal)
                        .frame(width: 40, height: 40)
                        .background(PulseColors.signal.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alt.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PulseColors.ink)
                        HStack(spacing: 6) {
                            Text("\(alt.sets) × \(alt.reps)")
                            if let notes = alt.notes, !notes.isEmpty {
                                Text("·")
                                Text(notes).lineLimit(1)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PulseColors.muted)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Example — watch proper form before you swap.
            Button {
                openYouTube(query: "\(alt.name) proper form")
                PulseHaptics.light()
            } label: {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(PulseColors.signal)
                    .frame(width: 38, height: 38)
                    .background(PulseColors.signal.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(PulseColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
    }

    // MARK: - Loading

    /// Ask the AI for same-muscle alternatives within the user's equipment.
    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        // No-AI path: same-muscle alternatives straight from the on-device
        // library. Instant, offline, free.
        if useLibrary {
            allAlternatives = WorkoutLibrary.alternatives(to: original).map { $0.asWorkoutExercise() }
            isLoading = false
            return
        }
        do {
            allAlternatives = try await PhotoTransformationService.shared.alternativeExercises(
                for: original.name,
                trainingStyle: trainingStyle,
                originalSets: original.sets
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - YouTube deep-link helper
//
// Opens the YouTube app to a search results page if installed; otherwise
// falls back to the YouTube web URL. Used by Example buttons throughout the
// transformation flow so the user sees a real video demonstrating proper form.
func openYouTube(query: String) {
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    let appURL = URL(string: "youtube://results?search_query=\(encoded)")!
    let webURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)")!
    if UIApplication.shared.canOpenURL(appURL) {
        UIApplication.shared.open(appURL)
    } else {
        UIApplication.shared.open(webURL)
    }
}

// MARK: - Meal Details Sheet
//
// Ported from the Claude Design "Pulse — Today" mock (May 27 redesign).
// Hero kcal ring, macro strip, real meal cards with SF Symbol meal-type
// glyphs, contextual today's-note. NO sample data — every number comes
// from MealLogService.todayEntries and TransformationPlan.dailyMacros.

struct MealDetailsSheet: View {
    let plan: TransformationPlan
    @Environment(\.dismiss) private var dismiss
    @State private var mealLog = MealLogService.shared
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingTextLog = false
    @State private var showingLogSheet = false
    @State private var capturedImage: UIImage?
    @State private var textDescription = ""
    // Correction flow: which entry is being corrected, and its draft text.
    @State private var correctingEntry: MealEntry?
    @State private var correctionText = ""

    // Toast shown briefly after a meal is logged
    @State private var toast: ToastInfo? = nil
    struct ToastInfo: Equatable {
        let name: String
        let kcal: Int
    }

    private var totals: DailyMacros { mealLog.totalsToday }
    private var caloriesLeft: Int { max(0, plan.dailyMacros.calories - totals.calories) }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft cream radial-gradient background per design
                PulseColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        dateHeader
                        heroRingCard.padding(.horizontal, 18)
                        macroStrip.padding(.horizontal, 18).padding(.top, 12)
                        mealsHeader.padding(.horizontal, 22).padding(.top, 24)
                        mealsList.padding(.horizontal, 18).padding(.top, 12)
                        todaysNote.padding(.horizontal, 18).padding(.top, 20)
                        Spacer(minLength: 130)
                    }
                    // Push the date header below the floating Back pill (8 top + 34 pill + 14 breathing room).
                    .padding(.top, 56)
                }

                // Floating "Log a meal" pill — fixed at the bottom center.
                VStack {
                    Spacer()
                    floatingLogButton
                        .padding(.bottom, 24)
                }

                // Toast confirmation when a meal is logged.
                if let t = toast {
                    VStack {
                        Spacer()
                        toastBanner(t).padding(.horizontal, 16).padding(.bottom, 96)
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Hide the system nav bar — the design uses a custom in-content
            // pill back button (top-left, surface bg, chevron + "Back"),
            // not iOS's default chevron-text.
            .toolbar(.hidden, for: .navigationBar)
            // Circular pill in the top-left — chevron only, no "Back" text.
            // Same footprint as the design's right-side settings button.
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PulseColors.ink)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(PulseColors.surface)
                                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                                .overlay(Circle().stroke(PulseColors.hair, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .onAppear { mealLog.load() }
            // Log-method sheet (Snap / Library / Describe)
            .sheet(isPresented: $showingLogSheet) {
                logMethodSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            // Camera + library + text-log entry points
            .sheet(isPresented: $showingCamera) { CameraImagePicker(image: $capturedImage) }
            .sheet(isPresented: $showingPhotoPicker) { MealPhotoPicker(image: $capturedImage) }
            .sheet(isPresented: $showingTextLog) { textLogSheet }
            .sheet(item: $correctingEntry) { entry in
                CorrectMealSheet(
                    entry: entry,
                    text: $correctionText,
                    isAnalyzing: mealLog.isAnalyzing
                ) { newText in
                    Task {
                        await mealLog.correctEntry(entry, userSaysItIs: newText)
                        correctingEntry = nil
                    }
                }
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: capturedImage) {
                guard let img = capturedImage else { return }
                let priorCount = mealLog.todayEntries.count
                Task {
                    await mealLog.logMealFromPhoto(img, userNote: nil)
                    capturedImage = nil
                    // Show toast for the newly-added entry (if any).
                    if mealLog.todayEntries.count > priorCount, let added = mealLog.todayEntries.last {
                        showToast(name: added.name, kcal: added.calories)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toast)
        }
    }

    // MARK: - Date header

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateLabel)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(PulseColors.textTertiary)
            Text("Today")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(PulseColors.ink)
                .tracking(-0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    // MARK: - Hero card (single kcal ring)

    private var heroRingCard: some View {
        VStack {
            HeroKcalRing(
                kcal: totals.calories,
                kcalGoal: plan.dailyMacros.calories,
                kcalLeft: caloriesLeft
            )
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(PulseColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 16, y: 6)
    }

    // MARK: - Macro strip (3 pills)

    private var macroStrip: some View {
        HStack(spacing: 10) {
            MacroPill(label: "PROTEIN",
                      consumed: totals.proteinGrams,
                      target: plan.dailyMacros.proteinGrams,
                      tint: PulseColors.signal)
            MacroPill(label: "CARBS",
                      consumed: totals.carbsGrams,
                      target: plan.dailyMacros.carbsGrams,
                      tint: PulseColors.signal.opacity(0.70))
            MacroPill(label: "FAT",
                      consumed: totals.fatGrams,
                      target: plan.dailyMacros.fatGrams,
                      tint: PulseColors.signal.opacity(0.45))
        }
    }

    // MARK: - Meals section

    private var mealsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Meals")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PulseColors.ink)
                .tracking(-0.3)
            Spacer()
            Text("\(mealLog.todayEntries.count) logged")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var mealsList: some View {
        VStack(spacing: 8) {
            if mealLog.todayEntries.isEmpty {
                emptyMealsCard
            } else {
                ForEach(mealLog.todayEntries) { entry in
                    MealRow(entry: entry, accent: PulseColors.signal, onCorrect: {
                        correctionText = entry.correctionNote ?? ""
                        correctingEntry = entry
                        PulseHaptics.light()
                    }, onDelete: {
                        mealLog.deleteEntry(entry)
                        PulseHaptics.light()
                    })
                }
            }
            if mealLog.isAnalyzing { analyzingRow }
            if let err = mealLog.lastError { errorRow(err) }
        }
    }

    private var emptyMealsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(PulseColors.signal.opacity(0.85))
            Text("No meals logged yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(PulseColors.ink)
            Text("Tap + below and snap a photo of your meal — we'll log the calories and macros for you. No weighing, no guessing.")
                .font(.system(size: 13))
                .foregroundColor(PulseColors.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PulseColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundColor(PulseColors.hair)
                )
        )
    }

    private var analyzingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.85)
            Text("AI is reading your meal…")
                .font(.system(size: 13))
                .foregroundColor(PulseColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func errorRow(_ msg: String) -> some View {
        Text(msg)
            .font(.system(size: 12))
            .foregroundColor(PulseColors.signal)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.signal.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Today's note (contextual, real %)

    private var todaysNote: some View {
        let pct = plan.dailyMacros.calories > 0
            ? Int(Double(totals.calories) / Double(plan.dailyMacros.calories) * 100)
            : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PulseColors.signal)
                Text("TODAY'S NOTE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(PulseColors.signal)
            }
            // Build the note from REAL macro data — no canned text.
            Text(noteString(pct: pct))
                .font(.system(size: 14.5))
                .foregroundColor(PulseColors.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
    }

    /// Build the contextual note from THIS user's actual numbers. No
    /// made-up advice — we just describe what we see.
    private func noteString(pct: Int) -> String {
        let proteinPct = plan.dailyMacros.proteinGrams > 0
            ? totals.proteinGrams * 100 / plan.dailyMacros.proteinGrams
            : 0
        let proteinHint: String
        if totals.calories == 0 {
            return "No meals logged yet today. Start with a high-protein breakfast — aim for \(plan.dailyMacros.proteinGrams / 4)g of protein in your first meal."
        }
        if proteinPct < 30 {
            proteinHint = "Protein is low so far — prioritize a protein-anchored next meal."
        } else if proteinPct >= 80 {
            proteinHint = "Protein is on track."
        } else {
            proteinHint = "Protein is building — keep including it in your remaining meals."
        }
        let caloriePart = pct >= 100
            ? "You've hit your calorie goal for today."
            : "You're \(pct)% to your calorie target — \(caloriesLeft.formatted()) kcal remaining."
        return "\(caloriePart) \(proteinHint)"
    }

    // MARK: - Floating log button

    private var floatingLogButton: some View {
        Button {
            showingLogSheet = true
            PulseHaptics.medium()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("Log a meal")
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(PulseColors.signal)
                    .shadow(color: PulseColors.signal.opacity(0.35), radius: 10, y: 6)
                    .shadow(color: PulseColors.signal.opacity(0.20), radius: 3, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log method sheet (Snap / Library / Describe)

    @ViewBuilder
    private var logMethodSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log a meal")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PulseColors.ink)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 18)

            // Primary: Snap a meal
            Button {
                showingLogSheet = false
                PulseHaptics.medium()
                // Wait for sheet dismiss before presenting camera (otherwise iOS
                // refuses to present a second sheet from the same view).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showingCamera = true
                }
            } label: {
                HStack(spacing: 14) {
                    iconTile(systemName: "camera.fill", onAccent: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snap a meal").font(.system(size: 16, weight: .semibold))
                        Text("Point your camera — AI logs it instantly")
                            .font(.system(size: 12.5))
                            .opacity(0.85)
                    }
                    .foregroundColor(.white)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(PulseColors.signal)
                        .shadow(color: PulseColors.signal.opacity(0.25), radius: 14, y: 8)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            // Secondary: 2 methods (Library + Describe)
            HStack(spacing: 10) {
                logMethodTile(title: "From Library", systemName: "photo.on.rectangle") {
                    showingLogSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingPhotoPicker = true
                    }
                }
                logMethodTile(title: "Describe", systemName: "text.cursor") {
                    showingLogSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingTextLog = true
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer(minLength: 18)
        }
        .padding(.top, 6)
        .background(PulseColors.background)
    }

    private func iconTile(systemName: String, onAccent: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(onAccent ? .white : PulseColors.signal)
            .frame(width: 44, height: 44)
            .background(onAccent
                        ? Color.white.opacity(0.16)
                        : PulseColors.signal.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func logMethodTile(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                iconTile(systemName: systemName, onAccent: false)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(PulseColors.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PulseColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PulseColors.hair, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text log

    private var textLogSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Describe what you ate")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PulseColors.ink)
                TextField("e.g. 2 eggs, toast with butter, coffee",
                          text: $textDescription, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Button {
                    let trimmed = textDescription
                    let priorCount = mealLog.todayEntries.count
                    Task {
                        await mealLog.logMealFromText(trimmed)
                        textDescription = ""
                        showingTextLog = false
                        if mealLog.todayEntries.count > priorCount, let added = mealLog.todayEntries.last {
                            showToast(name: added.name, kcal: added.calories)
                        }
                    }
                } label: {
                    Text("Log Meal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(textDescription.isEmpty ? PulseColors.muted : PulseColors.signal)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(textDescription.isEmpty)
                Spacer()
            }
            .padding(16)
            .pulseScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        textDescription = ""
                        showingTextLog = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Toast

    private func toastBanner(_ t: ToastInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(PulseColors.signal)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name).font(.system(size: 13.5, weight: .semibold)).foregroundColor(PulseColors.background)
                Text("Logged · \(t.kcal) kcal")
                    .font(.system(size: 11.5))
                    .foregroundColor(PulseColors.background.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PulseColors.ink)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }

    private func showToast(name: String, kcal: Int) {
        toast = ToastInfo(name: name, kcal: kcal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if toast?.name == name { toast = nil }
        }
    }
}

// MARK: - Hero kcal ring (single-ring per design spec)

private struct HeroKcalRing: View {
    let kcal: Int
    let kcalGoal: Int
    let kcalLeft: Int

    private var pct: Double {
        guard kcalGoal > 0 else { return 0 }
        return min(1.0, Double(kcal) / Double(kcalGoal))
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(PulseColors.signal.opacity(0.10), lineWidth: 12)
                .frame(width: 244, height: 244)
            // Progress
            Circle()
                .trim(from: 0, to: pct)
                .stroke(
                    PulseColors.signal,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 244, height: 244)
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: pct)

            VStack(spacing: 6) {
                Text("EATEN")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.7)
                    .foregroundColor(PulseColors.textTertiary)
                Text("\(kcal)")
                    .font(.system(size: 40, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.ink)
                    .tracking(-0.8)
                    .contentTransition(.numericText())
                Text("of \(kcalGoal.formatted()) kcal")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
                Text("\(kcalLeft.formatted()) LEFT")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(PulseColors.signal))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Macro pill (3 in a row under hero)

private struct MacroPill: View {
    let label: String
    let consumed: Int
    let target: Int
    let tint: Color

    private var pct: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(consumed) / Double(target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundColor(PulseColors.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Keep any value 0–999 g on ONE line — a 3-digit number like "100"
                // was wrapping to two lines ("10" / "0") in the narrow card. Scale
                // down before it ever wraps.
                Text("\(consumed)")
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.ink)
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ \(target)g")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(PulseColors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.18)).frame(height: 4)
                    Capsule().fill(tint)
                        .frame(width: max(0, geo.size.width * pct), height: 4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: pct)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(PulseColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
    }
}

// MARK: - Meal row

private struct MealRow: View {
    let entry: MealEntry
    let accent: Color
    let onCorrect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Meal-type icon tile — derived from the entry name so it's accurate.
            Image(systemName: MealRow.iconName(for: entry.name))
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(accent)
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.name)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(PulseColors.ink)
                        .tracking(-0.1)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("\(entry.calories)")
                            .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                            .foregroundColor(PulseColors.ink)
                        Text("kcal")
                            .font(.system(size: 13.5, design: .monospaced))
                            .foregroundColor(PulseColors.textTertiary)
                    }
                }
                HStack(spacing: 10) {
                    Text(timeString(entry.loggedAt))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(PulseColors.muted)
                    Circle().fill(PulseColors.textTertiary.opacity(0.6))
                        .frame(width: 3, height: 3)
                    HStack(spacing: 8) {
                        macroChip("P", entry.proteinGrams, color: PulseColors.signal)
                        macroChip("C", entry.carbsGrams, color: PulseColors.signal.opacity(0.70))
                        macroChip("F", entry.fatGrams, color: PulseColors.signal.opacity(0.45))
                    }
                }
            }
        }
        .padding(14)
        .background(PulseColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
        .contextMenu {
            Button(action: onCorrect) {
                Label("Correct / re-analyze", systemImage: "sparkles")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func macroChip(_ label: String, _ grams: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 11.5, weight: .semibold)).foregroundColor(color)
            Text("\(grams)").font(.system(size: 11.5, design: .monospaced)).foregroundColor(PulseColors.muted)
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// Map meal-name → SF Symbol icon. Heuristic but deterministic.
    static func iconName(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("salmon") || n.contains("fish") || n.contains("tuna") || n.contains("seafood") { return "fish.fill" }
        if n.contains("egg") { return "circle.fill" }
        if n.contains("yogurt") || n.contains("smoothie") || n.contains("coffee") || n.contains("latte") || n.contains("juice") || n.contains("shake") || n.contains("milk") { return "cup.and.saucer.fill" }
        if n.contains("toast") || n.contains("bread") || n.contains("sandwich") || n.contains("bagel") || n.contains("wrap") { return "takeoutbag.and.cup.and.straw.fill" }
        if n.contains("almond") || n.contains("nut") || n.contains("seed") || n.contains("granola") || n.contains("oats") || n.contains("oatmeal") { return "leaf.fill" }
        if n.contains("salad") || n.contains("veg") || n.contains("greens") || n.contains("spinach") || n.contains("kale") { return "leaf.fill" }
        if n.contains("steak") || n.contains("beef") || n.contains("burger") || n.contains("chicken") || n.contains("pork") || n.contains("turkey") || n.contains("bowl") { return "fork.knife" }
        if n.contains("rice") || n.contains("pasta") || n.contains("noodle") { return "fork.knife" }
        return "fork.knife"
    }
}

// MARK: - Correct / re-analyze a meal

private struct CorrectMealSheet: View {
    let entry: MealEntry
    @Binding var text: String
    let isAnalyzing: Bool
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHAT IS IT, REALLY?")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.2).foregroundColor(PulseColors.muted)
                    Text("Tell Pulse what this dish actually is and it'll re-estimate the macros from your photo.")
                        .font(.system(size: 13)).foregroundColor(PulseColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("e.g. grilled chicken caesar wrap, no dressing", text: $text, axis: .vertical)
                    .font(.system(size: 15)).lineLimit(2...4)
                    .focused($focused)
                    .padding(14).background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    PulseHaptics.medium()
                    onSubmit(trimmed)
                } label: {
                    HStack {
                        if isAnalyzing { ProgressView().tint(.white) }
                        Image(systemName: "sparkles")
                        Text(isAnalyzing ? "Re-analyzing…" : "Re-analyze")
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background((trimmed.isEmpty || isAnalyzing) ? PulseColors.muted.opacity(0.4) : PulseColors.signal)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(trimmed.isEmpty || isAnalyzing)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.top, 20)
            .pulseScreen()
            .navigationTitle("Correct meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(PulseColors.textSecondary)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Photo picker shim

struct MealPhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MealPhotoPicker
        init(_ p: MealPhotoPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage { parent.image = img }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Adjust Transformation Sheet
//
// Correct the AI's auto-detected body fat (it can be wrong) and add freeform
// instructions, then rebuild the plan from the SAME photos. AI-only: on
// failure nothing changes and the error (incl. "Usage limit hit") is shown.
struct AdjustTransformationSheet: View {
    let goal: Goal
    let plan: TransformationPlan
    var onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var service = PhotoTransformationService.shared

    @State private var currentBFText: String = ""
    @State private var targetBFText: String = ""
    @State private var instructions: String = ""
    @State private var working = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI ESTIMATE FROM YOUR PHOTOS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.2).foregroundColor(PulseColors.muted)
                        Text("Current \(plan.currentBodyFatPct)%  →  Goal \(plan.goalBodyFatPct)%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(PulseColors.ink)
                        Text("Pulse reads body fat from your photos automatically. If it got it wrong, correct it here — leave blank to keep the AI's number.")
                            .font(.system(size: 12)).foregroundColor(PulseColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        bfField(title: "CURRENT %", text: $currentBFText, placeholder: "\(plan.currentBodyFatPct)")
                        bfField(title: "TARGET %", text: $targetBFText, placeholder: "\(plan.goalBodyFatPct)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM INSTRUCTIONS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.2).foregroundColor(PulseColors.muted)
                        TextField("e.g. More upper-body focus, no jumping, 4 days a week, vegetarian meals…",
                                  text: $instructions, axis: .vertical)
                            .font(.system(size: 14)).lineLimit(3...6)
                            .padding(14).background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let e = errorMsg {
                        Text(e).font(.system(size: 12, weight: .medium)).foregroundColor(PulseColors.signal)
                    }

                    Button { rebuild() } label: {
                        HStack {
                            if working { ProgressView().tint(.white) }
                            Image(systemName: "wand.and.stars")
                            Text(working ? "Rebuilding your plan…" : "Rebuild my plan")
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(working ? PulseColors.muted.opacity(0.4) : PulseColors.signal)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(working)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.vertical, 16)
            }
            .pulseScreen()
            .dismissKeyboardOnTap()
            .navigationTitle("Adjust Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(PulseColors.textSecondary)
                }
            }
        }
    }

    private func bfField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.8).foregroundColor(PulseColors.muted)
            HStack(spacing: 4) {
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.ink)
                Text("%").font(.system(size: 14, design: .monospaced)).foregroundColor(PulseColors.muted)
            }
            .padding(12).background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func rebuild() {
        let id = goal.id?.uuidString ?? ""
        guard let curData = UserDefaults.standard.data(forKey: "transformation_current_\(id)"),
              let goalData = UserDefaults.standard.data(forKey: "transformation_goal_\(id)"),
              let curImg = UIImage(data: curData), let goalImg = UIImage(data: goalData) else {
            errorMsg = "Your original photos couldn't be found on this device, so the plan can't be rebuilt from them."
            return
        }
        var parts: [String] = []
        if let c = Double(currentBFText.trimmingCharacters(in: .whitespaces)) {
            parts.append("My measured CURRENT body fat is \(Int(c))% — use this EXACT value for currentBodyFatPct, do not re-estimate it.")
        }
        if let t = Double(targetBFText.trimmingCharacters(in: .whitespaces)) {
            parts.append("My target body fat is \(Int(t))% — use this EXACT value for goalBodyFatPct.")
        }
        let free = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !free.isEmpty { parts.append(free) }
        let combined = parts.isEmpty ? nil : parts.joined(separator: "\n")

        let style = TrainingStyle(rawValue: plan.trainingStyle) ?? .gym
        let unit = WeightUnit(rawValue: plan.weightUnit) ?? .lb

        working = true; errorMsg = nil
        Task {
            await service.generatePlan(
                currentPhoto: curImg, goalPhoto: goalImg,
                trainingStyle: style, weight: plan.weight, weightUnit: unit,
                targetWeeks: plan.estimatedWeeks, customInstructions: combined)
            await MainActor.run {
                working = false
                if let newPlan = service.analysisResult {
                    applyPlan(newPlan)
                    service.analysisResult = nil
                    PulseHaptics.success()
                    onApplied()
                    dismiss()
                } else {
                    errorMsg = service.error ?? "Couldn't rebuild the plan. Try again."
                }
            }
        }
    }

    private func applyPlan(_ newPlan: TransformationPlan) {
        goal.goalDescription = newPlan.assessment
        if let data = try? JSONEncoder().encode(newPlan), let json = String(data: data, encoding: .utf8) {
            goal.aiRoadmapJSON = json
        }
        if let existing = goal.dailyTasks as? Set<DailyTask> { existing.forEach { viewContext.delete($0) } }
        for workout in newPlan.workouts {
            let task = DailyTask(context: viewContext)
            task.id = UUID()
            task.title = workout.isRestDay ? "Rest day — \(workout.title)" : workout.title
            task.taskDescription = workout.focus
            task.howToDescription = workout.exercises.enumerated().map { idx, ex in
                let notes = ex.notes.map { " — \($0)" } ?? ""
                return "\(idx + 1). \(ex.name) — \(ex.sets) × \(ex.reps), rest \(ex.restSeconds)s\(notes)"
            }.joined(separator: "\n")
            task.proofType = "text"
            task.proofDescription = workout.isRestDay ? "Note any recovery work or how you felt." : "Tell us how the workout went."
            task.stepNumber = Int16(clamping: workout.dayOffset + 1)
            task.sortOrder = Int16(clamping: workout.dayOffset)
            task.estimatedMinutes = Int16(clamping: workout.estimatedMinutes)
            task.scheduledDate = Calendar.current.date(byAdding: .day, value: workout.dayOffset, to: Date())
            task.xpReward = 15
            task.verificationStatus = "pending"
            task.goal = goal
        }
        goal.updatedAt = Date()
        try? viewContext.save()
        Task.detached(priority: .utility) { try? await FirestoreSyncService.shared.syncGoal(goal) }
    }
}

// MARK: - Edit Exercise Sheet
//
// Set your own rep target (or "to failure") and rounds for an exercise. The
// live workout finishes the moment you hit the target — no waiting for the
// timer. Timed holds (plank etc.) edit the hold duration instead of reps.
struct EditExerciseSheet: View {
    let exercise: WorkoutExercise
    var onSave: (WorkoutExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 10
    @State private var rounds: Double = 3
    @State private var rest: Double = 60
    @State private var toFailure = false

    /// The three real editing styles, each with its own UI + copy:
    ///  • reps     — countable movements (push-ups, squats, jumping jacks). "How many?"
    ///  • hold     — static isometrics (plank, wall sit, superman). "Hold time".
    ///  • interval — continuous cardio (bike, rower, jump rope, boxing). "Work time".
    enum EditKind { case reps, hold, interval }

    private var kind: EditKind {
        let r = exercise.reps.lowercased()
        let n = exercise.name.lowercased()
        let timed = r.contains("sec") || r.contains("min")
        guard timed else { return .reps }   // a plain number = reps
        // Timed: decide hold vs work-interval. A "hold" is stationary; everything
        // else timed (cardio machines, jump rope, boxing, carries, crawls) is a
        // work interval — NOT a hold, so it never says "Hold time".
        let holdWords = ["plank", "hold", "wall sit", "hang", "carry", "boat",
                         "hollow", "superman", "bird dog", "pallof", "bear hold",
                         "suitcase", "l-sit", "lsit"]
        if holdWords.contains(where: { n.contains($0) }) { return .hold }
        return .interval
    }
    private var isTimed: Bool { kind != .reps }   // hold + interval both use seconds

    /// Recommended value parsed from the exercise's original prescription.
    /// "3 min" → 180s, "45 sec" → 45, "30" → 30 reps.
    private var recommended: Int {
        let r = exercise.reps.lowercased()
        let digits = Int(exercise.reps.filter(\.isNumber)) ?? (isTimed ? 30 : 10)
        if r.contains("min") { return digits * 60 }   // minutes → seconds
        return digits
    }
    private var unitLabel: String { isTimed ? "sec" : "reps" }
    private var sliderRange: ClosedRange<Double> { isTimed ? 10...600 : 1...1000 }

    /// The header label for the main slider, fitted to the exercise type.
    private var targetLabel: String {
        switch kind {
        case .reps:     return "HOW MANY REPS"
        case .hold:     return "HOLD TIME"
        case .interval: return "WORK TIME"
        }
    }
    /// The under-slider help text, fitted to the exercise type.
    private var targetHelp: String {
        switch kind {
        case .reps:     return "In Live mode the set completes the instant you hit this number of reps."
        case .hold:     return "The live timer counts down this hold and ends automatically."
        case .interval: return "The live timer counts down this work interval and ends automatically — keep moving the whole time."
        }
    }
    /// "Go to failure" only makes sense for rep-based moves.
    private var allowsToFailure: Bool { kind == .reps }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(exercise.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(PulseColors.ink)

                    // Rep / time target
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(targetLabel)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.2).foregroundColor(PulseColors.muted)
                            Spacer()
                            Text(toFailure ? "To failure" : "\(Int(value)) \(unitLabel)")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(PulseColors.signal)
                        }
                        Slider(value: $value, in: sliderRange, step: isTimed ? 5 : 1)
                            .tint(PulseColors.signal)
                            .disabled(toFailure)
                            .opacity(toFailure ? 0.4 : 1)
                        HStack {
                            Text("\(Int(sliderRange.lowerBound))")
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(PulseColors.muted)
                            Spacer()
                            Button {
                                value = Double(min(max(recommended, Int(sliderRange.lowerBound)), Int(sliderRange.upperBound)))
                                toFailure = false
                                PulseHaptics.light()
                            } label: {
                                Text("Recommended: \(recommended)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(PulseColors.signal)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(PulseColors.signal.opacity(0.1)).clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text("\(Int(sliderRange.upperBound))")
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(PulseColors.muted)
                        }
                        if allowsToFailure {
                            Toggle("Go to failure (no fixed number)", isOn: $toFailure)
                                .tint(PulseColors.signal)
                                .font(.system(size: 13))
                        }
                        Text(targetHelp)
                            .font(.system(size: 11)).foregroundColor(PulseColors.muted)
                    }

                    // Rounds
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ROUNDS")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.2).foregroundColor(PulseColors.muted)
                            Spacer()
                            Text("\(Int(rounds))")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(PulseColors.signal)
                        }
                        Slider(value: $rounds, in: 1...10, step: 1).tint(PulseColors.signal)
                    }

                    // Rest between rounds
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("REST BETWEEN ROUNDS")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.2).foregroundColor(PulseColors.muted)
                            Spacer()
                            Text(rest <= 0 ? "None" : "\(Int(rest))s")
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(PulseColors.signal)
                        }
                        Slider(value: $rest, in: 0...240, step: 5).tint(PulseColors.signal)
                        Text("How long the live timer rests you before the next round.")
                            .font(.system(size: 11)).foregroundColor(PulseColors.muted)
                    }

                    Button {
                        let reps = toFailure ? "Max" : (isTimed ? "\(Int(value)) sec" : "\(Int(value))")
                        let updated = WorkoutExercise(
                            name: exercise.name,
                            sets: Int(rounds),
                            reps: reps,
                            restSeconds: Int(rest),
                            notes: exercise.notes
                        )
                        onSave(updated)
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(PulseColors.signal)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.vertical, 16)
            }
            .pulseScreen()
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(PulseColors.textSecondary)
                }
            }
            .onAppear {
                value = Double(min(max(recommended, Int(sliderRange.lowerBound)), Int(sliderRange.upperBound)))
                rounds = Double(max(1, min(exercise.sets, 10)))
                rest = Double(max(0, min(exercise.restSeconds, 240)))
                toFailure = exercise.reps.lowercased().contains("max")
                    || exercise.reps.lowercased().contains("failure")
            }
        }
    }
}
