import Foundation
import CoreData
import WidgetKit

/// Writes app data to the shared App Group UserDefaults so WidgetKit widgets can read it.
final class WidgetDataService {
    static let shared = WidgetDataService()

    private let suiteName = "group.com.shimondeitel.pulsegoals"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    private init() {}

    /// Update all widget data from Core Data
    func updateWidgets(context: NSManagedObjectContext) {
        let request: NSFetchRequest<Goal> = Goal.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", GoalStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)]

        guard let goals = try? context.fetch(request) else { return }
        let primaryGoal = goals.first

        // Goal progress data
        defaults?.set(primaryGoal?.titleValue ?? "No active goal", forKey: "widget_goal_title")
        defaults?.set(primaryGoal?.id?.uuidString ?? "", forKey: "widget_goal_id")
        defaults?.set(primaryGoal?.completedSteps ?? 0, forKey: "widget_completed_pulses")
        defaults?.set(primaryGoal?.totalSteps ?? 0, forKey: "widget_total_pulses")
        defaults?.set(primaryGoal?.daysRemaining ?? 0, forKey: "widget_days_remaining")
        defaults?.set(Int(primaryGoal?.aiProbabilityScore ?? 0), forKey: "widget_probability")

        // Streak data
        let profileRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        let profile = (try? context.fetch(profileRequest))?.first
        defaults?.set(Int(profile?.currentStreak ?? 0), forKey: "widget_streak")
        defaults?.set(Int(profile?.longestStreak ?? 0), forKey: "widget_longest_streak")

        // Today's completion status
        let todayComplete = primaryGoal?.todaysTasks.allSatisfy { $0.isCompleted } ?? false
        defaults?.set(todayComplete, forKey: "widget_today_complete")

        // Next pulse + the one after it (so we can advance instantly on widget tap)
        let upcoming = primaryGoal?.allSteps.filter { !$0.isCompleted } ?? []
        if let nextStep = upcoming.first {
            defaults?.set(Int(nextStep.stepNumber), forKey: "widget_next_pulse_number")
            defaults?.set(nextStep.titleValue, forKey: "widget_next_pulse_title")
            defaults?.set(Int(nextStep.estimatedMinutes), forKey: "widget_next_pulse_minutes")
            defaults?.set(nextStep.id?.uuidString ?? "", forKey: "widget_next_pulse_id")
        } else {
            defaults?.set("", forKey: "widget_next_pulse_id")
            defaults?.set("All pulses done!", forKey: "widget_next_pulse_title")
        }
        if upcoming.count >= 2 {
            let after = upcoming[1]
            defaults?.set(Int(after.stepNumber), forKey: "widget_pulse_after_next_number")
            defaults?.set(after.titleValue, forKey: "widget_pulse_after_next_title")
            defaults?.set(Int(after.estimatedMinutes), forKey: "widget_pulse_after_next_minutes")
            defaults?.set(after.id?.uuidString ?? "", forKey: "widget_pulse_after_next_id")
        }

        // Level + XP (mirrors UserProfile+Extensions math)
        defaults?.set(Int(profile?.currentLevel ?? 1), forKey: "widget_level")
        defaults?.set(Int(profile?.totalXP ?? 0), forKey: "widget_total_xp")
        defaults?.set(Int(profile?.xpForNextLevel ?? 200), forKey: "widget_xp_for_next")
        defaults?.set(profile?.xpProgress ?? 0, forKey: "widget_xp_progress")

        // Today's pulses (scheduled for today)
        let todays = primaryGoal?.todaysTasks ?? []
        defaults?.set(todays.filter { $0.isCompleted }.count, forKey: "widget_today_done")
        defaults?.set(todays.count, forKey: "widget_today_total")

        // Timeline timestamps for live countdown widgets
        defaults?.set(primaryGoal?.deadline?.timeIntervalSince1970 ?? 0, forKey: "widget_deadline_ts")
        defaults?.set(primaryGoal?.createdAt?.timeIntervalSince1970 ?? 0, forKey: "widget_goal_start_ts")
        defaults?.set(primaryGoal != nil, forKey: "widget_has_goal")

        // Momentum — pulses completed in the last 7 days vs the 7 before that
        let taskReq: NSFetchRequest<DailyTask> = DailyTask.fetchRequest()
        let now = Date()
        let fourteenAgo = now.addingTimeInterval(-14 * 86_400)
        taskReq.predicate = NSPredicate(format: "isCompleted == YES AND completedDate >= %@", fourteenAgo as CVarArg)
        let doneTasks = (try? context.fetch(taskReq)) ?? []
        let sevenAgo = now.addingTimeInterval(-7 * 86_400)
        let recent = doneTasks.filter { ($0.completedDate ?? .distantPast) >= sevenAgo }.count
        let prior = doneTasks.count - recent
        let momentum: String
        if recent == 0 && prior == 0 { momentum = "steady" }
        else if recent > prior { momentum = "rising" }
        else if recent < prior { momentum = "declining" }
        else { momentum = "steady" }
        defaults?.set(momentum, forKey: "widget_momentum")
        defaults?.set(recent, forKey: "widget_momentum_recent")
        defaults?.set(prior, forKey: "widget_momentum_prior")

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Apply any pulse completions queued by the interactive widget.
    /// Returns the IDs of pulses that were synced so the app can fire
    /// celebrations or analytics.
    @discardableResult
    func syncPendingWidgetCompletions(context: NSManagedObjectContext) -> [String] {
        guard let pending = defaults?.array(forKey: "pending_completions") as? [[String: String]],
              !pending.isEmpty else { return [] }

        var synced: [String] = []
        for entry in pending {
            guard let pulseIDString = entry["pulse_id"],
                  let pulseUUID = UUID(uuidString: pulseIDString) else { continue }

            let req: NSFetchRequest<DailyTask> = DailyTask.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", pulseUUID as CVarArg)
            req.fetchLimit = 1

            if let task = (try? context.fetch(req))?.first, !task.isCompleted {
                task.isCompleted = true
                task.completedDate = ISO8601DateFormatter().date(from: entry["completed_at"] ?? "") ?? Date()
                task.verificationStatus = "verified"
                synced.append(pulseIDString)

                // Credit the completion through the ONE canonical path: it awards
                // the XP, re-derives the level, advances the daily streak, saves,
                // and refreshes the widget. This is the SINGLE award for a widget
                // completion — PulseApp.syncWidgetCompletions no longer also awards.
                if let profile = task.goal?.userProfile {
                    profile.registerCompletion(xp: Int(task.xpReward), in: context)
                }
            }
        }
        try? context.save()
        defaults?.removeObject(forKey: "pending_completions")
        // Refresh widget data after sync
        updateWidgets(context: context)
        return synced
    }
}
