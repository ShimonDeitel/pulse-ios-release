import SwiftUI
import CoreData

// MARK: - Custom Workout builder (no AI, no photos, offline, free)
//
// Hand-pick exercises from the on-device WorkoutLibrary into training days,
// tune rounds/reps/rest, name the plan + weeks, and save. Produces the SAME
// TransformationPlan + DailyTask shape the workout engine already renders, but
// under category "workout" so it's never Pro-gated and never touches AI.
struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    struct BuilderDay: Identifiable {
        let id = UUID()
        var title: String
        var exercises: [WorkoutExercise]
    }

    struct EditTarget: Identifiable {
        let id = UUID()
        let dayIndex: Int
        let exercise: WorkoutExercise
    }

    // Codable snapshot of the builder's structured @State so it survives a
    // Cancel + reopen ("Continue Custom Workout"). WorkoutExercise is already
    // Codable; we only persist the plain fields (computed `id`s aren't stored).
    private struct BuilderDraft: Codable {
        struct Day: Codable {
            var title: String
            var exercises: [WorkoutExercise]
        }
        var planName: String
        var weeks: Int
        var days: [Day]
        var activeDayIndex: Int
    }

    private static let draftKey = "pulse_draft_workout_builder"

    @State private var planName: String = "My Workout Plan"
    @State private var weeks: Int = 4
    @State private var days: [BuilderDay] = [BuilderDay(title: "Day 1", exercises: [])]
    @State private var activeDayIndex: Int = 0
    @State private var showingPicker = false
    @State private var editTarget: EditTarget?
    // True once we've attempted a restore this lifetime, so a sheet re-appear
    // mid-edit never clobbers live @State with a stale snapshot.
    @State private var hasRestored = false

    private var canSave: Bool { days.contains { !$0.exercises.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Plan name", text: $planName)
                        .font(.system(size: 16, weight: .semibold))
                    Stepper("Length: \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...12)
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Built-in exercises with automatic rep-counting — no AI, no photos. Free.")
                }

                ForEach(days.indices, id: \.self) { di in
                    Section {
                        if days[di].exercises.isEmpty {
                            Text("No exercises yet")
                                .font(.system(size: 13))
                                .foregroundColor(PulseColors.muted)
                        } else {
                            ForEach(days[di].exercises) { ex in
                                Button {
                                    editTarget = EditTarget(dayIndex: di, exercise: ex)
                                } label: {
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
                            if days.count > 1 {
                                Button(role: .destructive) {
                                    days.remove(at: di)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        days.append(BuilderDay(title: "Day \(days.count + 1)", exercises: []))
                        PulseHaptics.light()
                    } label: {
                        Label("Add training day", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .navigationTitle("Custom Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveManualPlan() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                LibraryPickerSheet { libExercise in
                    if days.indices.contains(activeDayIndex) {
                        days[activeDayIndex].exercises.append(libExercise.asWorkoutExercise())
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
            .onAppear { restoreDraftIfPresent() }
            .onChange(of: planName) { persistDraft() }
            .onChange(of: weeks) { persistDraft() }
            .onChange(of: activeDayIndex) { persistDraft() }
            // `days` (and its nested exercises) isn't Equatable, so observe a
            // cheap structural signature instead — fires on add/remove/edit.
            .onChange(of: daysSignature) { persistDraft() }
        }
    }

    // MARK: - Draft persistence (self-contained; UserDefaults JSON)

    // Compact, Equatable fingerprint of `days` so .onChange can detect any
    // structural mutation (day added/removed/renamed, exercise added/removed/edited).
    private var daysSignature: String {
        days.map { day in
            day.title + "|" + day.exercises.map { "\($0.name):\($0.sets):\($0.reps):\($0.restSeconds):\($0.notes ?? "")" }.joined(separator: ",")
        }.joined(separator: "~")
    }

    private func persistDraft() {
        let draft = BuilderDraft(
            planName: planName,
            weeks: weeks,
            days: days.map { BuilderDraft.Day(title: $0.title, exercises: $0.exercises) },
            activeDayIndex: activeDayIndex
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: Self.draftKey)
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
    }

    private func restoreDraftIfPresent() {
        // Restore at most once per lifetime, and never over an in-progress edit:
        // only hydrate when the view is still in its pristine initial state.
        guard !hasRestored else { return }
        hasRestored = true
        guard isPristine,
              let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let draft = try? JSONDecoder().decode(BuilderDraft.self, from: data),
              !draft.days.isEmpty else { return }

        planName = draft.planName
        weeks = min(max(draft.weeks, 1), 12)
        days = draft.days.map { BuilderDay(title: $0.title, exercises: $0.exercises) }
        activeDayIndex = min(max(draft.activeDayIndex, 0), days.count - 1)
    }

    // The untouched initial state: default name, one empty day, no exercises.
    private var isPristine: Bool {
        planName == "My Workout Plan"
            && weeks == 4
            && days.count == 1
            && days.first?.exercises.isEmpty == true
    }

    // MARK: - Exercise row

    private func exerciseRow(_ ex: WorkoutExercise) -> some View {
        HStack(spacing: 12) {
            Image(systemName: WorkoutLibrary.all.first(where: { $0.name == ex.name })?.symbol
                  ?? "figure.strengthtraining.traditional")
                .font(.system(size: 16))
                .foregroundColor(PulseColors.signal)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PulseColors.textPrimary)
                Text("\(ex.sets) × \(ex.reps) · rest \(ex.restSeconds)s")
                    .font(.system(size: 12))
                    .foregroundColor(PulseColors.textSecondary)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundColor(PulseColors.textTertiary)
        }
    }

    // MARK: - Save (offline, no AI)

    private func focusLabel(for exercises: [WorkoutExercise]) -> String {
        var seen = Set<String>()
        var groups: [String] = []
        for ex in exercises {
            if let g = WorkoutLibrary.all.first(where: { $0.name == ex.name })?.muscleGroup.displayName,
               !seen.contains(g) {
                seen.insert(g)
                groups.append(g)
            }
        }
        return groups.isEmpty ? "Training" : groups.prefix(3).joined(separator: ", ")
    }

    private func saveManualPlan() {
        let usableDays = days.filter { !$0.exercises.isEmpty }
        guard !usableDays.isEmpty else { return }

        let workouts: [DailyWorkout] = usableDays.enumerated().map { idx, day in
            DailyWorkout(
                dayOffset: idx,
                title: day.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Day \(idx + 1)" : day.title,
                focus: focusLabel(for: day.exercises),
                estimatedMinutes: pulseWorkoutMinutes(day.exercises),
                exercises: day.exercises,
                isRestDay: false
            )
        }

        var plan = TransformationPlan(
            assessment: "",
            estimatedWeeks: weeks,
            currentBodyFatPct: 0,
            goalBodyFatPct: 0,
            dailyMacros: DailyMacros(calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0),
            mealsGuidance: "",
            workouts: workouts,
            weeklyMilestones: [],
            habits: [],
            trainingStyle: "manual",
            weight: 0,
            weightUnit: "lb"
        )
        plan.isManual = true

        let goal = Goal(context: viewContext)
        goal.id = UUID()
        goal.title = planName.trimmingCharacters(in: .whitespaces).isEmpty ? "Workout Plan" : planName
        goal.goalDescription = "Custom workout plan"
        goal.category = "workout"          // NEW category — never Pro-gated (see GoalDetailRouter)
        goal.status = GoalStatus.active.rawValue
        goal.deadline = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: Date())
        goal.currentProgress = 0
        goal.availableTimePerDay = 60
        goal.skillLevel = SkillLevel.beginner.rawValue
        goal.motivationLevel = 8
        goal.urgencyLevel = UrgencyLevel.medium.rawValue
        goal.createdAt = Date()

        if let data = try? JSONEncoder().encode(plan),
           let json = String(data: data, encoding: .utf8) {
            goal.aiRoadmapJSON = json
        }

        let profile = UserProfile.fetchOrCreate(in: viewContext)
        goal.userProfile = profile

        // One DailyTask per workout day — mirrors PhotoTransformationView so the
        // calendar + completion + celebration machinery works unchanged.
        for workout in workouts {
            let task = DailyTask(context: viewContext)
            task.id = UUID()
            task.title = workout.title
            task.taskDescription = workout.focus
            task.howToDescription = workout.exercises.enumerated().map { i, ex in
                let notes = ex.notes.map { " — \($0)" } ?? ""
                return "\(i + 1). \(ex.name) — \(ex.sets) × \(ex.reps), rest \(ex.restSeconds)s\(notes)"
            }.joined(separator: "\n")
            task.proofType = "text"
            task.proofDescription = "Tell us how the workout went."
            task.stepNumber = Int16(clamping: workout.dayOffset + 1)
            task.sortOrder = Int16(clamping: workout.dayOffset)
            task.estimatedMinutes = Int16(clamping: workout.estimatedMinutes)
            task.scheduledDate = Calendar.current.date(byAdding: .day, value: workout.dayOffset, to: Date())
            task.xpReward = 15
            task.verificationStatus = "pending"
            task.goal = goal
        }

        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)
        clearDraft()   // plan created — discard the saved builder snapshot
        AdaptiveNotificationScheduler.shared.refreshFromSettings()
        PulseHaptics.success()
        DispatchQueue.main.async { dismiss() }
    }
}

// MARK: - Library picker sheet (browse / filter / search the on-device catalog)

struct LibraryPickerSheet: View {
    let onAdd: (LibraryExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var muscle: MuscleGroup?
    @State private var equipment: Equipment?
    // Confirmation that a tap actually landed: `justAdded` drives the brief
    // green checkmark flash on the + button; `addedCounts` keeps a persistent
    // "Added ✓ / Added ×N" badge so the user can see what's already in the plan.
    @State private var justAdded: Set<String> = []
    @State private var addedCounts: [String: Int] = [:]

    private var results: [LibraryExercise] {
        var list = WorkoutLibrary.search(search)
        if let m = muscle { list = list.filter { $0.muscleGroup == m } }
        if let e = equipment { list = list.filter { $0.equipment == e } }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                Divider()
                List(results) { ex in
                    libraryRow(ex)
                }
                .listStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func libraryRow(_ ex: LibraryExercise) -> some View {
        let count = addedCounts[ex.id] ?? 0
        let flashing = justAdded.contains(ex.id)
        HStack(spacing: 12) {
            Image(systemName: ex.symbol)
                .font(.system(size: 16))
                .foregroundColor(PulseColors.signal)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PulseColors.textPrimary)
                if count > 0 {
                    Label(count == 1 ? "Added to plan" : "Added ×\(count)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(PulseColors.green)
                } else {
                    // Every catalog exercise is camera-tracked — show whether it's
                    // rep-counted or a timed hold so the trackability is visible.
                    HStack(spacing: 5) {
                        Image(systemName: ex.coaching.isAutoCounted ? "number.circle.fill" : "timer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(PulseColors.signal)
                        Text("\(ex.coaching.isAutoCounted ? "Auto-counted" : "Timed hold") · \(ex.muscleGroup.displayName) · \(ex.defaultSets)×\(ex.defaultReps)")
                            .font(.system(size: 11.5))
                            .foregroundColor(PulseColors.textSecondary)
                    }
                }
            }
            Spacer()
            Button {
                openYouTube(query: "\(ex.name) proper form")
            } label: {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(PulseColors.textTertiary)
            }
            .buttonStyle(.plain)
            Button {
                addFromLibrary(ex)
            } label: {
                Image(systemName: flashing ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(flashing ? PulseColors.green : PulseColors.signal)
                    .scaleEffect(flashing ? 1.18 : 1.0)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func addFromLibrary(_ ex: LibraryExercise) {
        onAdd(ex)
        let id = ex.id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            addedCounts[id, default: 0] += 1
            _ = justAdded.insert(id)
        }
        PulseHaptics.success()
        // Revert the flash to "+" after a beat so they can add it again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.25)) { _ = justAdded.remove(id) }
        }
    }

    private var filterChips: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MuscleGroup.allCases) { g in
                        chip(g.displayName, systemImage: g.icon, on: muscle == g) {
                            muscle = (muscle == g) ? nil : g
                        }
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Equipment.allCases) { e in
                        chip(e.displayName, systemImage: e.icon, on: equipment == e) {
                            equipment = (equipment == e) ? nil : e
                        }
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
            }
        }
        .padding(.vertical, 10)
    }

    private func chip(_ label: String, systemImage: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(label).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundColor(on ? .white : PulseColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? PulseColors.signal : PulseColors.surfaceElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
