import Foundation
import UserNotifications
import CoreData

/// Schedules notifications adaptively based on the user's state — NOT on a
/// manual timer. The user only flips a single on/off switch; this service
/// reads goals, streaks, deadlines, and activity to decide when (and what)
/// to send.
///
/// Triggers it watches:
///   • Streak risk         — about to break their streak (no pulse done today, past 6pm)
///   • Daily nudge         — no activity yet today, at user's usual active hour
///   • Deadline pressure   — final 7 days of a goal, daily check-in
///   • Milestone unlock    — celebrate completed pulses
///   • Personality mentor  — one nudge per day from the chosen mentor personality
final class AdaptiveNotificationScheduler {
    static let shared = AdaptiveNotificationScheduler()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// The id for the single gentle "you have no goal yet" nudge shown ONLY when
    /// the user has zero active goals. Kept inside `allIdentifiers` so refresh()
    /// clears it up front — that both prevents duplicates AND guarantees it is
    /// removed the moment a goal exists (the >=1 branch never reschedules it)
    /// and when notifications are toggled OFF (refresh() removes it before the
    /// `guard enabled` return).
    private let startAGoalIdentifier = "pulse.start-a-goal"

    private let allIdentifiers = [
        "pulse.streak-risk",
        "pulse.daily-nudge",
        "pulse.deadline-pressure",
        "pulse.mentor-checkin",
        "pulse.start-a-goal"
    ]

    /// Cancel the per-goal check-in + evening reminders scheduled for a goal
    /// (see GoalInputViewModel.scheduleCheckInNotifications). MUST be called on
    /// goal deletion — otherwise a deleted goal keeps firing daily reminders
    /// forever, which is exactly the "notifications for goals I deleted" bug.
    static func cancelGoalNotifications(goalID: String) {
        guard !goalID.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["checkin-\(goalID)", "evening-\(goalID)"])
    }

    /// Call exactly once when a goal becomes completed: cancel that goal's
    /// per-goal reminders AND rebuild the global daily set so the 6pm
    /// "How did your pulse go? log it" check-in stops referencing a finished
    /// goal (it re-points to the next active goal, or the start-a-goal nudge).
    @MainActor
    static func handleGoalCompletion(goalID: String) {
        cancelGoalNotifications(goalID: goalID)
        shared.refreshFromSettings()
    }

    /// Self-heal users stranded by older completion paths: any ACTIVE goal whose
    /// every step is already done is flipped to `.completed`. Those paths used to
    /// mark the last step done without flipping status, so the daily
    /// "How did your pulse go? log it" check-in kept firing forever. Idempotent
    /// and safe to run on every launch / foreground. Returns true if it changed
    /// anything (so the caller can refresh the schedule).
    @MainActor
    @discardableResult
    static func migrateStrandedCompletedGoals() -> Bool {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<Goal> = Goal.fetchRequest()
        req.predicate = NSPredicate(format: "status == %@", GoalStatus.active.rawValue)
        let active = (try? ctx.fetch(req)) ?? []
        var changed = false
        for g in active where g.markCompletedIfAllStepsDone() { changed = true }
        if changed { try? ctx.save() }
        return changed
    }

    /// Sweep pending check-in / evening reminders whose goal no longer exists
    /// and cancel them. Fixes goals deleted BEFORE the cancel-on-delete fix
    /// that were still nagging. Safe to call on every launch / foreground.
    @MainActor
    static func reconcileOrphanedGoalNotifications() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<Goal> = Goal.fetchRequest()
        // Only ACTIVE goals keep their per-goal reminders. A completed/paused/
        // abandoned goal still exists in Core Data, so without this filter its
        // checkin-/evening- reminders count as "live" and nag forever. Scoping
        // to active also self-heals users already stranded by a past completion.
        req.predicate = NSPredicate(format: "status == %@", GoalStatus.active.rawValue)
        let liveIDs = Set(((try? ctx.fetch(req)) ?? []).compactMap { $0.id?.uuidString })
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let orphans = requests.map(\.identifier).filter { idf in
                (idf.hasPrefix("checkin-") || idf.hasPrefix("evening-")) &&
                !liveIDs.contains(String(idf.dropFirst(8)))
            }
            if !orphans.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: orphans)
            }
        }
    }

    /// Refresh all adaptive notifications. Call after enabling, after a pulse
    /// is completed, after a goal is created, and on app foreground.
    func refresh(enabled: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)
        guard enabled else { return }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                self.scheduleAll()
            }
        }
    }

    /// Convenience wrapper so call sites don't each re-derive the on/off flag.
    /// Reads the single user toggle "pulse_notifications_enabled" with the
    /// app-wide default of ON (matches PulseApp.onAppear and the Notifications
    /// sheet). Using `.bool(forKey:)` directly would wrongly read `false` on a
    /// fresh install where the key was never written.
    func refreshFromSettings() {
        let enabled = UserDefaults.standard.object(forKey: "pulse_notifications_enabled") as? Bool ?? true
        refresh(enabled: enabled)
    }

    @MainActor
    private func scheduleAll() {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<Goal> = Goal.fetchRequest()
        req.predicate = NSPredicate(format: "status == %@", GoalStatus.active.rawValue)

        // GOAL-AWARE BRANCH:
        //  • 0 active goals -> NO goal-referencing notification. Send ONE gentle,
        //    non-goal "start a goal" nudge instead, and sweep any leftover
        //    per-goal checkin-/evening- reminders (with no live goal they are all
        //    orphans, so reconcileOrphanedGoalNotifications removes exactly them).
        //  • >=1 active goal -> the existing 4 goal notifications (unchanged).
        //    The start-a-goal nudge was already cleared by refresh() up front and
        //    is intentionally NOT rescheduled here, so it disappears.
        // Pick the first goal that still has work left. A goal whose every step
        // is done must NEVER drive the daily "How did your pulse go? log it"
        // reminders — even if its status field somehow lags behind (defense in
        // depth on top of the status==active predicate above). If none qualify,
        // fall through to the start-a-goal nudge.
        guard let goals = try? ctx.fetch(req),
              let goal = goals.first(where: { $0.totalSteps == 0 || $0.completedSteps < $0.totalSteps }) else {
            scheduleStartAGoalNudge(in: ctx)
            AdaptiveNotificationScheduler.reconcileOrphanedGoalNotifications()
            return
        }

        let personality = MentorPersonality(rawValue: goal.userProfile?.mentorPersonality ?? "coach") ?? .coach
        let goalName = goal.titleValue
        let daysLeft = goal.daysRemaining

        // Has the user already completed a pulse today? If so, suppress the
        // 10am "you haven't done your pulse" and 8pm "your streak is at risk"
        // — both are noise on a day already-done.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let anyTaskDoneToday: Bool = {
            guard let tasks = goal.dailyTasks as? Set<DailyTask> else { return false }
            return tasks.contains { task in
                guard task.isCompleted, let done = task.completedDate else { return false }
                return cal.isDate(done, inSameDayAs: today)
            }
        }()

        // 1. Daily nudge at 10am — only if there's an incomplete pulse today
        if !anyTaskDoneToday {
            scheduleAt(hour: 10, minute: 0,
                       identifier: "pulse.daily-nudge",
                       title: nudgeTitle(personality: personality),
                       body: dailyBody(personality: personality, goal: goalName))
        }

        // 2. Streak-risk at 8pm — fires if streak still alive but pulse undone
        if !anyTaskDoneToday {
            scheduleAt(hour: 20, minute: 0,
                       identifier: "pulse.streak-risk",
                       title: streakTitle(personality: personality),
                       body: streakBody(personality: personality, goal: goalName))
        }

        // 3. Deadline pressure — only if final 7 days
        if daysLeft <= 7 && daysLeft > 0 {
            scheduleAt(hour: 9, minute: 0,
                       identifier: "pulse.deadline-pressure",
                       title: "Pulse",
                       body: deadlineBody(personality: personality, goal: goalName, daysLeft: daysLeft))
        }

        // 4. Mentor check-in at 6pm — one personality-flavored message per day
        scheduleAt(hour: 18, minute: 0,
                   identifier: "pulse.mentor-checkin",
                   title: personality.displayName,
                   body: mentorBody(personality: personality, goal: goalName))
    }

    /// The zero-goal nudge: ONE gentle, NON-goal-referencing daily reminder to
    /// start a goal. Repeats daily at 11:00 (a fire-once reminder would go silent
    /// forever). Personality-flavored from the user's profile if one exists (a
    /// profile can exist with no goal); falls back to .coach. Contains NO goal name.
    @MainActor
    private func scheduleStartAGoalNudge(in ctx: NSManagedObjectContext) {
        let preq: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        preq.fetchLimit = 1
        let personality = (try? ctx.fetch(preq))?.first?.mentorPersonalityEnum ?? .coach
        scheduleAt(hour: 11, minute: 0,
                   identifier: startAGoalIdentifier,
                   title: startAGoalTitle(personality: personality),
                   body: startAGoalBody(personality: personality))
    }

    private func startAGoalTitle(personality: MentorPersonality) -> String {
        switch personality {
        case .military:   return "NO MISSION SET"
        case .aggressive: return "PICK A TARGET"
        case .highEnergy: return "LET'S START SOMETHING"
        case .friendly:   return "Hey"
        default:          return "Pulse"
        }
    }

    /// Deliberately mentions NO goal name — there is no goal yet.
    private func startAGoalBody(personality: MentorPersonality) -> String {
        switch personality {
        case .military:       return "You have no objective. Set one. Open Pulse and pick your mission."
        case .aggressive:     return "Nothing to chase yet. What do you want? Open Pulse and set a goal."
        case .brutallyHonest: return "You haven't set a goal. Nothing happens until you do. Open Pulse."
        case .minimalist:     return "No goal yet. Set one."
        case .highEnergy:     return "Your first goal is waiting! Open Pulse and let's GO."
        case .calm:           return "When you're ready, open Pulse and choose one goal to begin."
        case .friendly:       return "What do you want to achieve? Open Pulse and start your first goal."
        default:              return "You haven't set a goal yet — what do you want to achieve? Open Pulse to start."
        }
    }

    private func scheduleAt(hour: Int, minute: Int, identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Personality-aware copy

    private func nudgeTitle(personality: MentorPersonality) -> String {
        switch personality {
        case .military:      return "FALL IN, RECRUIT"
        case .aggressive:    return "WAKE UP"
        case .highEnergy:    return "LET'S GO"
        case .calm:          return "Gentle reminder"
        case .friendly:      return "Hey"
        default:             return "Pulse"
        }
    }

    private func dailyBody(personality: MentorPersonality, goal: String) -> String {
        switch personality {
        case .military:
            return "Today's pulse for \(goal) is waiting. Execute the mission."
        case .aggressive:
            return "Your competition is moving on \(goal). Are you?"
        case .brutallyHonest:
            return "Pulse undone. \(goal) doesn't finish itself."
        case .supportive:
            return "Today's pulse for \(goal) is ready when you are."
        case .highEnergy:
            return "LET'S CRUSH today's pulse on \(goal)!"
        case .calm:
            return "When you're ready, today's pulse for \(goal) awaits."
        case .friendly:
            return "Just a heads up — your pulse for \(goal) is queued up."
        case .minimalist:
            return "\(goal). One pulse."
        case .disciplined:
            return "Today's pulse on \(goal) — system before motivation."
        case .coach:
            return "Game plan check-in: today's pulse for \(goal) is on the board."
        }
    }

    private func streakTitle(personality: MentorPersonality) -> String {
        switch personality {
        case .military:      return "STREAK AT RISK"
        case .aggressive:    return "DON'T QUIT NOW"
        default:             return "Streak risk"
        }
    }

    private func streakBody(personality: MentorPersonality, goal: String) -> String {
        switch personality {
        case .military:    return "Streak about to break. Get it done. NOW."
        case .supportive:  return "Your streak is so close to safe — one pulse keeps it alive."
        case .friendly:    return "Heads up — your streak ends at midnight if no pulse today."
        case .minimalist:  return "Streak. Tonight. Don't break it."
        default:           return "Your streak ends at midnight if today's pulse goes undone."
        }
    }

    private func deadlineBody(personality: MentorPersonality, goal: String, daysLeft: Int) -> String {
        "Final \(daysLeft) days for \(goal). Today's pulse is critical."
    }

    private func mentorBody(personality: MentorPersonality, goal: String) -> String {
        // Personality-flavored evening check-in. Static phrasing for now;
        // a future iteration can call Groq for fresh wording each day.
        switch personality {
        case .coach:          return "How did today's pulse on \(goal) go? Open Pulse to log it."
        case .military:       return "Report status on \(goal). Open the app."
        case .supportive:     return "Just checking in on you and \(goal). You're doing great."
        case .aggressive:     return "Status check on \(goal). Open up."
        case .brutallyHonest: return "Real talk: where are you on \(goal) today?"
        case .minimalist:     return "\(goal). Status?"
        case .highEnergy:     return "How's \(goal) going CHAMPION?"
        case .calm:           return "A moment to reflect on \(goal)."
        case .disciplined:    return "Did today's pulse on \(goal) get executed? Log it."
        case .friendly:       return "Hey! How'd \(goal) go today?"
        }
    }
}
