import Foundation
import CoreData

extension UserProfile {
    var displayNameValue: String {
        get { displayName ?? "User" }
        set { displayName = newValue }
    }

    /// Whether the user has a real, self-identifying name (vs. the generic
    /// "User" placeholder or nothing at all). Sign in with Apple only returns
    /// the name on the FIRST authorization, so on returning sign-ins / the
    /// simulator we may have no name — this lets the app prompt for one instead
    /// of silently displaying "User".
    var hasRealName: Bool {
        let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare("User") != .orderedSame
    }

    var mentorPersonalityEnum: MentorPersonality {
        get { MentorPersonality(rawValue: mentorPersonality ?? "coach") ?? .coach }
        set { mentorPersonality = newValue.rawValue }
    }

    var levelValue: Int { Int(computedLevel) }

    /// Level derived PURELY from totalXP — the ONE leveling curve used app-wide
    /// (100 XP per level: lvl 1 = 0–99, lvl 2 = 100–199, …). `registerCompletion`
    /// keeps the stored `currentLevel` in lockstep with this, so screens that read
    /// the stored field and screens that read this can never disagree.
    var computedLevel: Int32 { Int32(max(0, totalXP) / 100) + 1 }

    /// XP needed to advance one level — always the per-level size (linear curve).
    var xpForNextLevel: Int32 { 100 }

    /// Fraction (0…1) of the current level completed; drives the XP progress bar.
    /// Linear and matched to `computedLevel`, so the bar actually fills.
    var xpProgress: Double {
        Double(max(0, totalXP) % 100) / 100.0
    }

    var goalsArray: [Goal] {
        let set = goals as? Set<Goal> ?? []
        return set.sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    var achievementsArray: [Achievement] {
        let set = achievements as? Set<Achievement> ?? []
        return set.sorted { ($0.unlockedDate ?? Date.distantPast) > ($1.unlockedDate ?? Date.distantPast) }
    }

    var activeGoals: [Goal] {
        goalsArray.filter { $0.statusEnum == .active }
    }

    static func fetchOrCreate(in context: NSManagedObjectContext) -> UserProfile {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }
        let profile = UserProfile(context: context)
        profile.id = UUID()
        // Leave displayName nil — `displayNameValue` still renders "User" as a
        // safe default, but keeping the stored value empty lets `hasRealName`
        // detect that we still need to capture/prompt for the real name.
        profile.displayName = nil
        profile.mentorPersonality = MentorPersonality.coach.rawValue
        profile.currentLevel = 1
        profile.totalXP = 0
        profile.currentStreak = 0
        profile.longestStreak = 0
        profile.onboardingCompleted = false
        return profile
    }

    // MARK: - Canonical completion (XP · level · streak · save · widget)
    //
    // EVERY pulse / workout-day completion in the app MUST go through these so the
    // SAME action always credits the SAME XP, advances the SAME level (one linear
    // curve), moves the daily streak, persists, and refreshes the home-screen
    // widget — no matter which screen it was completed from. Do NOT mutate
    // totalXP / currentLevel / currentStreak anywhere else.

    /// Credit one completion. `xp` is normally `Int(task.xpReward)`. Awards the
    /// XP, re-derives the level, advances the streak, saves, and refreshes the
    /// home-screen widget. Returns true if this was the first activity today.
    @discardableResult
    func registerCompletion(xp: Int, in context: NSManagedObjectContext) -> Bool {
        totalXP = max(0, totalXP + Int64(max(0, xp)))
        currentLevel = computedLevel
        let firstToday = registerActivityForToday()
        try? context.save()
        WidgetDataService.shared.updateWidgets(context: context)
        return firstToday
    }

    /// Reverse a completion (un-check): subtract the same XP (clamped at 0) and
    /// re-derive the level. Leaves the streak alone — a mistaken un-check
    /// shouldn't erase a day already earned.
    func unregisterCompletion(xp: Int, in context: NSManagedObjectContext) {
        totalXP = max(0, totalXP - Int64(max(0, xp)))
        currentLevel = computedLevel
        try? context.save()
        WidgetDataService.shared.updateWidgets(context: context)
    }

    /// Advance the daily streak from `lastActiveDate`. Idempotent within a day:
    /// +1 if the last active day was yesterday, reset to 1 after a gap, no-op if
    /// already counted today. Returns true on the first activity today.
    @discardableResult
    func registerActivityForToday() -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let last = lastActiveDate {
            let lastDay = cal.startOfDay(for: last)
            if lastDay == today { return false }
            let gap = cal.dateComponents([.day], from: lastDay, to: today).day ?? 99
            currentStreak = (gap == 1) ? currentStreak + 1 : 1
        } else {
            currentStreak = 1
        }
        longestStreak = max(longestStreak, currentStreak)
        lastActiveDate = today
        return true
    }
}
