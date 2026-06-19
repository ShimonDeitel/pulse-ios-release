import SwiftUI
import CoreData

/// DEDICATED entry point for "Daily Habit" goals.
///
/// Habit name, category, time-of-day, duration, streak length. Generates one
/// DailyTask per day in the streak window and milestone markers at common
/// streak intervals. No AI call — the structure is uniform by definition.
struct DailyHabitGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var title = ""
    @State private var selectedCategory: GoalCategory = .personal
    @State private var timeOfDay = "Morning"
    @State private var duration: Double = 30
    @State private var streakGoal: Double = 30
    @State private var isCreating = false

    private let timesOfDay = ["Morning", "Afternoon", "Evening", "Anytime"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "repeat.circle.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(PulseColors.signal)
                        Text("New Daily Habit")
                            .font(PulseTypography.headlineLarge)
                            .foregroundColor(PulseColors.textPrimary)
                            .headlineTracking()
                        Text("Build consistency one day at a time")
                            .font(PulseTypography.bodyMedium)
                            .foregroundColor(PulseColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Habit name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HABIT NAME")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)
                        TextField("", text: $title, prompt: Text("e.g. Meditate for 10 minutes").foregroundColor(PulseColors.textTertiary))
                            .font(PulseTypography.bodyLarge)
                            .foregroundColor(PulseColors.textPrimary)
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Category
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CATEGORY")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(GoalCategory.allCases) { cat in
                                Button {
                                    selectedCategory = cat
                                    PulseHaptics.light()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.iconName)
                                            .font(.system(size: 12))
                                        Text(cat.displayName)
                                            .font(PulseTypography.labelMedium)
                                    }
                                    .foregroundColor(selectedCategory == cat ? PulseColors.onPrimary : PulseColors.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selectedCategory == cat ? PulseColors.mono : PulseColors.surfaceContainer)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Time of day
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BEST TIME")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)

                        HStack(spacing: 8) {
                            ForEach(timesOfDay, id: \.self) { time in
                                Button {
                                    timeOfDay = time
                                } label: {
                                    Text(time)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(timeOfDay == time ? PulseColors.onPrimary : PulseColors.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(timeOfDay == time ? PulseColors.mono : PulseColors.surfaceContainer)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Duration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("DURATION PER DAY")
                                .font(PulseTypography.eyebrow)
                                .eyebrowTracking()
                                .foregroundColor(PulseColors.textTertiary)
                            Spacer()
                            Text("\(Int(duration)) min")
                                .font(PulseTypography.monoCaption)
                                .foregroundColor(PulseColors.signal)
                        }
                        Slider(value: $duration, in: 5...120, step: 5)
                            .tint(PulseColors.signal)
                    }

                    // Streak goal
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("STREAK GOAL")
                                .font(PulseTypography.eyebrow)
                                .eyebrowTracking()
                                .foregroundColor(PulseColors.textTertiary)
                            Spacer()
                            Text("\(Int(streakGoal)) days")
                                .font(PulseTypography.monoCaption)
                                .foregroundColor(PulseColors.signal)
                        }
                        Slider(value: $streakGoal, in: 7...365, step: 7)
                            .tint(PulseColors.signal)
                    }

                    // Create
                    Button {
                        createHabit()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "repeat.circle.fill")
                            Text(isCreating ? "Creating..." : "Start Habit")
                        }
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(PulseColors.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PulseColors.mono)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(title.isEmpty || isCreating)
                    .opacity(title.isEmpty ? 0.5 : 1)
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, 40)
            }
            .pulseScreen()
            .navigationTitle("Daily Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            // Resume a saved Daily Habit draft: restore every typed/selected field
            // (name, category, best time, duration, streak goal) so backing out and
            // re-entering never loses what you'd entered.
            .onAppear {
                let f = DraftService.shared.draftFields(.habit)
                if let t = f["title"], !t.isEmpty { title = t }
                if let c = f["category"], let cat = GoalCategory(rawValue: c) { selectedCategory = cat }
                if let tod = f["timeOfDay"], timesOfDay.contains(tod) { timeOfDay = tod }
                if let d = f["duration"], let n = Double(d) { duration = n }
                if let s = f["streakGoal"], let n = Double(s) { streakGoal = n }
            }
            // Persist each field the moment it changes so a draft never goes stale.
            .onChange(of: title) { persistDraftFields() }
            .onChange(of: selectedCategory) { persistDraftFields() }
            .onChange(of: timeOfDay) { persistDraftFields() }
            .onChange(of: duration) { persistDraftFields() }
            .onChange(of: streakGoal) { persistDraftFields() }
        }
    }

    /// Persist the in-progress Daily Habit inputs into the draft so they survive
    /// backing out and are restored on resume. Cleared once the habit is created.
    private func persistDraftFields() {
        guard !isCreating else { return }
        DraftService.shared.saveDraftFields(.habit, [
            "title": title,
            "category": selectedCategory.rawValue,
            "timeOfDay": timeOfDay,
            "duration": String(Int(duration)),
            "streakGoal": String(Int(streakGoal))
        ])
    }

    private func createHabit() {
        isCreating = true
        let goal = Goal(context: viewContext)
        goal.id = UUID()
        goal.title = title
        goal.goalDescription = "Daily habit: \(title) (\(timeOfDay), \(Int(duration))min)"
        goal.category = selectedCategory.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.deadline = Calendar.current.date(byAdding: .day, value: Int(streakGoal), to: Date())
        goal.currentProgress = 0
        goal.availableTimePerDay = Float(duration)
        goal.createdAt = Date()

        let profile = UserProfile.fetchOrCreate(in: viewContext)
        goal.userProfile = profile

        let days = Int(streakGoal)
        for day in 1...days {
            let task = DailyTask(context: viewContext)
            task.id = UUID()
            task.title = "\(title)"
            task.howToDescription = "Complete your daily habit: \(title). Best time: \(timeOfDay). Duration: \(Int(duration)) minutes."
            task.proofDescription = "Mark as done when completed"
            task.proofType = "text"
            task.stepNumber = Int16(clamping: day)
            task.sortOrder = Int16(clamping: day)
            task.estimatedMinutes = Int16(clamping: Int(duration))
            task.xpReward = 10
            task.isCompleted = false
            task.verificationStatus = "pending"
            task.scheduledDate = Calendar.current.date(byAdding: .day, value: day - 1, to: Date())
            task.goal = goal
        }

        let milestoneIntervals = [7, 14, 30, 60, 90, 180, 365].filter { $0 <= days }
        for (index, interval) in milestoneIntervals.enumerated() {
            let milestone = Milestone(context: viewContext)
            milestone.id = UUID()
            milestone.title = "\(interval)-Day Streak!"
            milestone.sortOrder = Int16(index)
            milestone.weekNumber = Int16(interval / 7 + 1)
            milestone.xpReward = Int32(interval)
            milestone.isCompleted = false
            milestone.goal = goal
        }

        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)

        // The habit is now a real goal — drop its saved draft fields so a future
        // Daily Habit starts blank and onChange re-saves won't resurrect it.
        DraftService.shared.clearDraftFields(.habit)

        Task { try? await FirestoreSyncService.shared.syncGoal(goal) }

        AdaptiveNotificationScheduler.shared.refreshFromSettings()
        PulseHaptics.heavy()
        dismiss()
    }
}
