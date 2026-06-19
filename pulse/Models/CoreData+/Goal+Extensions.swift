import Foundation
import CoreData

extension Goal {
    var titleValue: String {
        get { title ?? "Untitled Goal" }
        set { title = newValue }
    }

    var categoryEnum: GoalCategory {
        get { GoalCategory(rawValue: category ?? "personal") ?? .personal }
        set { category = newValue.rawValue }
    }

    var statusEnum: GoalStatus {
        get { GoalStatus(rawValue: status ?? "active") ?? .active }
        set { status = newValue.rawValue }
    }

    /// True when this goal needs AI (it's a transformation goal or was built with
    /// AI on a paid plan) but the user is currently on Free. Single source of truth
    /// for the Pro-lock decision — mirrors exactly what GoalDetailRouter gates on,
    /// so every surface (router, dashboard, list) locks the same set of goals and a
    /// downgraded Free user can't complete paid AI content for free.
    var isLockedForCurrentTier: Bool {
        (category == "transformation" || ProGoalRegistry.isPro(id?.uuidString))
            && !SubscriptionManager.shared.hasAIGeneration
    }

    /// Flip an active goal to `.completed` once every step is done. Returns true
    /// only on the transition, so callers know to run the one-time completion
    /// side effects (cancel this goal's reminders, refresh the schedule, fire the
    /// celebration). Idempotent: returns false if already completed or unfinished.
    /// This is the SINGLE source of truth for "the goal is finished" — every
    /// step-completion path funnels through it so no path can leave a finished
    /// goal stuck `.active` (which is what kept the daily "log it" reminder firing).
    @discardableResult
    func markCompletedIfAllStepsDone() -> Bool {
        // Workout AND transformation plans REPEAT across their whole duration —
        // finishing the 7-day template training days once is not "done", so they
        // stay active (and on the Home screen) until the user ends them or the
        // deadline passes. Only one-shot goals (regular pulses) auto-complete when
        // every step is done.
        guard category != "workout", category != "transformation" else { return false }
        guard statusEnum != .completed,
              totalSteps > 0,
              completedSteps >= totalSteps else { return false }
        statusEnum = .completed
        currentProgress = 100
        return true
    }

    var daysRemaining: Int {
        guard let deadline = deadline else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0)
    }

    var progressPercentage: Double {
        // Always reflect the REAL pulses completed, so every progress bar (home
        // card, widgets, Progress tab) matches the "X / Y pulses" count exactly.
        // The stored `currentProgress` isn't updated by every completion path
        // (home-screen widget, celebration, live workout), so deriving it live
        // from the actual steps keeps all surfaces honest and consistent.
        let total = totalSteps
        if total > 0 {
            return min(1.0, Double(completedSteps) / Double(total))
        }
        // Goals with no step list (e.g. a metric-only goal) fall back to the
        // stored value so they still show meaningful progress.
        return min(1.0, max(0.0, Double(currentProgress) / 100.0))
    }

    var milestonesArray: [Milestone] {
        let set = milestones as? Set<Milestone> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder }
    }

    var dailyTasksArray: [DailyTask] {
        let set = dailyTasks as? Set<DailyTask> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder }
    }

    var allSteps: [DailyTask] {
        let set = dailyTasks as? Set<DailyTask> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder }
    }

    var completedSteps: Int {
        allSteps.filter { $0.isCompleted }.count
    }

    var totalSteps: Int {
        allSteps.count
    }

    var currentStepIndex: Int {
        allSteps.firstIndex { !$0.isCompleted } ?? allSteps.count
    }

    var nextStep: DailyTask? {
        allSteps.first { !$0.isCompleted }
    }

    var todaysTasks: [DailyTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return dailyTasksArray.filter { task in
            guard let scheduled = task.scheduledDate else { return false }
            return calendar.isDate(scheduled, inSameDayAs: today)
        }
    }

    var completedTodaysTasks: Int {
        todaysTasks.filter { $0.isCompleted }.count
    }

    var progressEntriesArray: [ProgressEntry] {
        let set = progressEntries as? Set<ProgressEntry> ?? []
        return set.sorted { ($0.entryDate ?? .distantPast) > ($1.entryDate ?? .distantPast) }
    }

    var mentorMessagesArray: [MentorMessage] {
        let set = mentorMessages as? Set<MentorMessage> ?? []
        return set.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    var focusSessionsArray: [FocusSession] {
        let set = focusSessions as? Set<FocusSession> ?? []
        return set.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
    }

    var totalFocusMinutes: Int {
        focusSessionsArray.reduce(0) { $0 + Int($1.actualDurationMinutes) }
    }

    var urgencyLevelEnum: UrgencyLevel {
        if daysRemaining <= 3 { return .critical }
        if daysRemaining <= 7 { return .high }
        if daysRemaining <= 14 { return .medium }
        return .low
    }
}
