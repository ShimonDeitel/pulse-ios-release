import SwiftUI
import CoreData

// MARK: - Custom Workout detail (no-AI, no-photo, free)
//
// The lean detail screen for a hand-built "Custom Workout" goal (category
// "workout"). It reuses the proven, on-device workout engine — WorkoutCalendar,
// TodayWorkoutSheet (Live mode + rep-counting skeleton), and library-backed Swap
// — but deliberately shows NONE of the AI/photo/meal UI from TransformationDetail.
// Everything here is offline and free.
struct CustomWorkoutDetailView: View {
    @ObservedObject var goal: Goal
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState

    @State private var plan: TransformationPlan?
    @State private var showingWorkoutSheet = false
    @State private var showingAddWorkouts = false
    @State private var showingChat = false

    // MARK: Derived

    private var daysSinceStart: Int {
        let start = goal.createdAt ?? Date()
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day],
                                         from: cal.startOfDay(for: start),
                                         to: cal.startOfDay(for: Date())).day ?? 0)
    }

    private var currentWeek: Int { max(1, daysSinceStart / 7 + 1) }

    private var totalWeeks: Int { max(1, plan?.estimatedWeeks ?? max(1, (goal.daysRemaining + 6) / 7)) }

    /// Today's session: exact day match on the first pass, then the plan repeats.
    private var todayWorkout: DailyWorkout? {
        guard let workouts = plan?.workouts, !workouts.isEmpty else { return nil }
        if let exact = workouts.first(where: { $0.dayOffset == daysSinceStart }) { return exact }
        return workouts[daysSinceStart % workouts.count]
    }

    private var doneCount: Int {
        (goal.dailyTasks as? Set<DailyTask>)?.filter { $0.isCompleted }.count ?? 0
    }
    private var totalCount: Int { goal.dailyTasksArray.count }

    /// Whether TODAY's session is already marked complete (its DailyTask is done).
    ///
    /// Keyed on the ABSOLUTE day index (`daysSinceStart + 1`), not the recycled
    /// `todayWorkout.dayOffset`. On the first pass these are identical (the exact
    /// match guarantees `dayOffset == daysSinceStart`), but once the plan repeats
    /// (`daysSinceStart % count`) the recycled workout's small dayOffset would map
    /// back onto an earlier day's DailyTask — so day 8 looked "done" merely because
    /// day 1 was. Using the absolute index lets each calendar day track on its own.
    private var todayIsComplete: Bool {
        guard todayWorkout != nil else { return false }
        let target = Int16(clamping: daysSinceStart + 1)
        return (goal.dailyTasks as? Set<DailyTask>)?
            .contains { $0.stepNumber == target && $0.isCompleted } ?? false
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                WorkoutCalendar(goal: goal)
                startButton
                    .padding(.top, 8)
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
                Button {
                    PulseHaptics.light()
                    showingChat = true
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PulseColors.ink)
                }
                .accessibilityLabel("Chat about this goal")
            }
            // Plus icon — tap to add more workouts to this plan directly.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    PulseHaptics.light()
                    showingAddWorkouts = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(PulseColors.ink)
                }
                .accessibilityLabel("Add Workouts")
            }
        }
        .task { loadPlan() }
        .sheet(isPresented: $showingWorkoutSheet) {
            if let workout = todayWorkout, let plan = plan {
                // useLibrary: true → Swap pulls same-muscle alternatives from the
                // on-device library (no AI). Live mode + rep-counting are on-device.
                TodayWorkoutSheet(workout: workout, plan: plan, goal: goal, useLibrary: true)
                    .environment(\.managedObjectContext, viewContext)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $showingAddWorkouts) {
            AddWorkoutsSheet(goal: goal) { loadPlan() }
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingChat) {
            NavigationStack { MentorChatView(fixedGoal: goal) }
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("WEEK \(currentWeek) OF \(totalWeeks)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.85))
            }

            Text(goal.titleValue)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 24) {
                statCell("\(doneCount)/\(totalCount)", "DONE")
                statCell("\(max(0, goal.daysRemaining))", "DAYS LEFT")
                statCell("\(plan?.workouts.count ?? 0)", "SESSIONS")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [PulseColors.signal, PulseColors.signal.opacity(0.82)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Start

    @ViewBuilder private var startButton: some View {
        if let workout = todayWorkout {
            Button {
                PulseHaptics.medium()
                showingWorkoutSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: todayIsComplete ? "checkmark.circle.fill" : "play.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todayIsComplete ? "Today's Workout Completed" : "Start Today's Workout")
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(workout.title) · \(workout.exercises.count) exercises")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                // Green once today's session is done; brand red otherwise. (`ink`
                // is cream in dark mode, which would hide the white label.)
                .background(todayIsComplete ? PulseColors.green : PulseColors.signal)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            Text("No exercises in this plan yet.")
                .font(.system(size: 13))
                .foregroundColor(PulseColors.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Load

    private func loadPlan() {
        if let jsonData = goal.aiRoadmapJSON?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(TransformationPlan.self, from: jsonData) {
            plan = decoded
        }
    }
}

// MARK: - Add Workouts sheet (offline, no AI)
//
// Reached from the detail screen's three-dots menu. Loads the existing plan's
// training days, lets the user add exercises (from the on-device library) to any
// day, add whole new training days, edit rounds/reps/rest, or remove items —
// then rewrites the plan JSON and reconciles the per-day DailyTask rows so the
// calendar stays in sync. No AI, no photos.
private struct AddWorkoutsSheet: View {
    @ObservedObject var goal: Goal
    let onSaved: () -> Void
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    struct EditableDay: Identifiable {
        let id = UUID()
        var title: String
        var dayOffset: Int
        var exercises: [WorkoutExercise]
        var isNew: Bool
    }
    struct EditTarget: Identifiable {
        let id = UUID()
        let dayIndex: Int
        let exercise: WorkoutExercise
    }

    @State private var days: [EditableDay] = []
    @State private var activeDayIndex = 0
    @State private var showingPicker = false
    @State private var editTarget: EditTarget?
    @State private var loaded = false

    private var canSave: Bool { days.contains { !$0.exercises.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days.indices, id: \.self) { di in
                    Section {
                        if days[di].exercises.isEmpty {
                            Text("No exercises yet")
                                .font(.system(size: 13)).foregroundColor(PulseColors.muted)
                        } else {
                            ForEach(days[di].exercises) { ex in
                                Button { editTarget = EditTarget(dayIndex: di, exercise: ex) } label: {
                                    exerciseRow(ex)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in days[di].exercises.remove(atOffsets: offsets) }
                        }
                        Button {
                            activeDayIndex = di
                            showingPicker = true
                        } label: {
                            Label("Add exercise", systemImage: "plus.circle.fill")
                                .foregroundColor(PulseColors.signal)
                        }
                    } header: {
                        HStack {
                            TextField("Day name", text: $days[di].title)
                                .font(.system(size: 13, weight: .semibold))
                                .textInputAutocapitalization(.words)
                            Spacer()
                            // Only newly-added days can be removed wholesale —
                            // existing days keep their completion history.
                            if days[di].isNew {
                                Button(role: .destructive) { days.remove(at: di) } label: {
                                    Image(systemName: "trash").font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        let nextOffset = (days.map { $0.dayOffset }.max() ?? -1) + 1
                        days.append(EditableDay(title: "Day \(days.count + 1)", dayOffset: nextOffset, exercises: [], isNew: true))
                        PulseHaptics.light()
                    } label: {
                        Label("Add training day", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle("Add Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(PulseColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                LibraryPickerSheet { lib in
                    if days.indices.contains(activeDayIndex) {
                        days[activeDayIndex].exercises.append(lib.asWorkoutExercise())
                    }
                }
            }
            .sheet(item: $editTarget) { target in
                EditExerciseSheet(exercise: target.exercise) { updated in
                    if days.indices.contains(target.dayIndex),
                       let i = days[target.dayIndex].exercises.firstIndex(where: { $0.id == target.exercise.id }) {
                        days[target.dayIndex].exercises[i] = updated
                    }
                    editTarget = nil
                }
            }
            .task { if !loaded { load(); loaded = true } }
        }
    }

    private func exerciseRow(_ ex: WorkoutExercise) -> some View {
        HStack(spacing: 12) {
            Image(systemName: WorkoutLibrary.all.first(where: { $0.name == ex.name })?.symbol
                  ?? "figure.strengthtraining.traditional")
                .font(.system(size: 16)).foregroundColor(PulseColors.signal).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.system(size: 15, weight: .medium)).foregroundColor(PulseColors.textPrimary)
                Text("\(ex.sets) × \(ex.reps) · rest \(ex.restSeconds)s")
                    .font(.system(size: 12)).foregroundColor(PulseColors.textSecondary)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3").font(.system(size: 12)).foregroundColor(PulseColors.textTertiary)
        }
    }

    private func focusLabel(for exercises: [WorkoutExercise]) -> String {
        var seen = Set<String>(); var groups: [String] = []
        for ex in exercises {
            if let g = WorkoutLibrary.all.first(where: { $0.name == ex.name })?.muscleGroup.displayName, !seen.contains(g) {
                seen.insert(g); groups.append(g)
            }
        }
        return groups.isEmpty ? "Training" : groups.prefix(3).joined(separator: ", ")
    }

    private func load() {
        guard let jsonData = goal.aiRoadmapJSON?.data(using: .utf8),
              let plan = try? JSONDecoder().decode(TransformationPlan.self, from: jsonData) else {
            days = [EditableDay(title: "Day 1", dayOffset: 0, exercises: [], isNew: true)]
            return
        }
        days = plan.workouts.map { EditableDay(title: $0.title, dayOffset: $0.dayOffset, exercises: $0.exercises, isNew: false) }
        if days.isEmpty { days = [EditableDay(title: "Day 1", dayOffset: 0, exercises: [], isNew: true)] }
    }

    private func save() {
        let usable = days.filter { !$0.exercises.isEmpty }
        guard !usable.isEmpty,
              let jsonData = goal.aiRoadmapJSON?.data(using: .utf8),
              let old = try? JSONDecoder().decode(TransformationPlan.self, from: jsonData) else { dismiss(); return }

        let rebuilt: [DailyWorkout] = usable.enumerated().map { idx, d in
            DailyWorkout(
                dayOffset: d.dayOffset,
                title: d.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Day \(idx + 1)" : d.title,
                focus: focusLabel(for: d.exercises),
                estimatedMinutes: pulseWorkoutMinutes(d.exercises),
                exercises: d.exercises,
                isRestDay: false
            )
        }

        // TransformationPlan.workouts is `let`, so rebuild the struct preserving
        // every other field (and the stable id + manual flag).
        var newPlan = TransformationPlan(
            assessment: old.assessment,
            estimatedWeeks: old.estimatedWeeks,
            currentBodyFatPct: old.currentBodyFatPct,
            goalBodyFatPct: old.goalBodyFatPct,
            dailyMacros: old.dailyMacros,
            mealsGuidance: old.mealsGuidance,
            workouts: rebuilt,
            weeklyMilestones: old.weeklyMilestones,
            habits: old.habits,
            trainingStyle: old.trainingStyle,
            weight: old.weight,
            weightUnit: old.weightUnit
        )
        newPlan.id = old.id
        newPlan.isManual = old.isManual ?? true

        if let data = try? JSONEncoder().encode(newPlan), let s = String(data: data, encoding: .utf8) {
            goal.aiRoadmapJSON = s
        }

        // Reconcile DailyTasks: match an existing task by sortOrder == dayOffset
        // (update title + how-to); create a fresh task for any new day so the
        // calendar shows it. We don't delete tasks for emptied days (keeps history).
        var bySort: [Int16: DailyTask] = [:]
        for t in goal.dailyTasksArray { bySort[t.sortOrder] = t }
        let startDate = goal.createdAt ?? Date()
        for w in rebuilt {
            let key = Int16(clamping: w.dayOffset)
            let task: DailyTask
            if let existing = bySort[key] {
                task = existing
            } else {
                task = DailyTask(context: viewContext)
                task.id = UUID()
                task.proofType = "text"
                task.proofDescription = "Tell us how the workout went."
                task.xpReward = 15
                task.verificationStatus = "pending"
                task.goal = goal
                task.scheduledDate = Calendar.current.date(byAdding: .day, value: w.dayOffset, to: startDate)
            }
            task.title = w.title
            task.taskDescription = w.focus
            task.howToDescription = w.exercises.enumerated().map { i, ex in
                let notes = ex.notes.map { " — \($0)" } ?? ""
                return "\(i + 1). \(ex.name) — \(ex.sets) × \(ex.reps), rest \(ex.restSeconds)s\(notes)"
            }.joined(separator: "\n")
            task.stepNumber = Int16(clamping: w.dayOffset + 1)
            task.sortOrder = key
            task.estimatedMinutes = Int16(clamping: w.estimatedMinutes)
        }

        try? viewContext.save()
        AdaptiveNotificationScheduler.shared.refreshFromSettings()
        PulseHaptics.success()
        onSaved()
        DispatchQueue.main.async { dismiss() }
    }
}
