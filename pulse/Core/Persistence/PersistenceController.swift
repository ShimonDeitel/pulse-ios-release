import CoreData
import UserNotifications

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext

        // Create sample user profile
        let profile = UserProfile(context: ctx)
        profile.id = UUID()
        profile.displayName = "Alex"
        profile.mentorPersonality = "coach"
        profile.currentLevel = 5
        profile.totalXP = 1250
        profile.currentStreak = 7
        profile.longestStreak = 14
        profile.onboardingCompleted = true
        profile.lastActiveDate = Date()

        // Create sample goal
        let goal = Goal(context: ctx)
        goal.id = UUID()
        goal.title = "Learn SwiftUI"
        goal.goalDescription = "Master SwiftUI framework"
        goal.category = GoalCategory.learning.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.deadline = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        goal.currentProgress = 0
        goal.aiProbabilityScore = 78.0
        goal.motivationLevel = 8
        goal.skillLevel = SkillLevel.intermediate.rawValue
        goal.userProfile = profile

        // Create sample milestone
        let milestone = Milestone(context: ctx)
        milestone.id = UUID()
        milestone.title = "Complete fundamentals"
        milestone.isCompleted = true
        milestone.sortOrder = 0
        milestone.xpReward = 50
        milestone.goal = goal

        // Create sample tasks
        for i in 0..<3 {
            let task = DailyTask(context: ctx)
            task.id = UUID()
            task.title = "Task \(i + 1)"
            task.scheduledDate = Date()
            task.isCompleted = false   // never pre-complete a task (it read as "done today" you didn't do)
            task.sortOrder = Int16(i)
            task.xpReward = 10
            task.estimatedMinutes = 30
            task.goal = goal
        }

        // Create sample achievement
        let achievement = Achievement(context: ctx)
        achievement.id = UUID()
        achievement.title = "First Goal"
        achievement.achievementDescription = "Created your first goal"
        achievement.achievementType = "first_goal"
        achievement.unlockedDate = Date()
        achievement.xpReward = 50
        achievement.iconName = "star.fill"
        achievement.userProfile = profile

        try? ctx.save()
        return controller
    }()

    let container: NSPersistentCloudKitContainer

    /// The iCloud container that backs the private store. This is a FIXED
    /// identifier (it is NOT derived from the bundle id — the app is
    /// `com.shimondeitel.pulse` but the container is `…pulsegoals`). It must
    /// match the CloudKit capability in Signing & Capabilities AND a container
    /// of this exact id provisioned in the Apple Developer portal.
    static let cloudKitContainerID = "iCloud.com.shimondeitel.pulsegoals"

    /// One-time wipe of stored AI-chat history. The "previous chats" feature was
    /// removed; chat is now session-only, so any MentorMessage rows persisted by
    /// older builds are dead data. Delete them once (CloudKit-safe fetch+delete)
    /// so they also stop syncing to iCloud.
    static func purgeMentorMessagesOnce(in context: NSManagedObjectContext) {
        let key = "pulse_did_purge_mentor_history_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let req = NSFetchRequest<NSManagedObject>(entityName: "MentorMessage")
        if let rows = try? context.fetch(req), !rows.isEmpty {
            rows.forEach { context.delete($0) }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "pulse")

        // Normally the container synthesizes a default store description. If it
        // somehow doesn't, create and attach a fresh one instead of crashing on
        // launch — graceful degradation beats a fatalError in front of a user.
        let description: NSPersistentStoreDescription
        if let existing = container.persistentStoreDescriptions.first {
            description = existing
        } else {
            description = NSPersistentStoreDescription()
            container.persistentStoreDescriptions = [description]
        }

        if inMemory {
            // Previews / unit tests: in-memory, never touch CloudKit.
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
        } else {
            // NSPersistentCloudKitContainer requires persistent history tracking
            // and remote-change notifications so local edits sync to iCloud and
            // changes from the user's other devices merge back in. (Kept on even
            // for the local-only path so CloudKit can attach later with no
            // store migration once iCloud becomes available.)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            // Attach CloudKit ONLY when the device is actually signed into iCloud.
            // Without an account (e.g. Simulator, signed-out device, or before the
            // container is provisioned), NSPersistentCloudKitContainer's ASYNC
            // mirroring setup can hard-trap (EXC_BREAKPOINT in
            // PFCloudKitContainerProvider) — which the loadPersistentStores error
            // fallback below cannot catch because it fires after a successful load.
            // Gating on ubiquityIdentityToken keeps the app launchable everywhere;
            // sync switches on automatically on the next launch once iCloud is
            // available, with no store migration.
            if FileManager.default.ubiquityIdentityToken != nil {
                // Sync the whole store to the signed-in user's PRIVATE iCloud DB.
                // Each Apple ID gets its own isolated copy — no server, no keys.
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: PersistenceController.cloudKitContainerID
                )
            } else {
                print("[Persistence] No iCloud account — starting local-only; CloudKit attaches on a later launch once signed in.")
                description.cloudKitContainerOptions = nil
            }
        }

        var loadError: NSError?
        container.loadPersistentStores { _, error in
            if let error = error as NSError? { loadError = error }
        }

        // CloudKit can refuse to attach when the iCloud container isn't
        // provisioned yet (Xcode capability / dev-portal not configured) or the
        // device isn't signed into iCloud. Never crash over that — retry as a
        // LOCAL-ONLY store so the app always launches. Sync simply switches on
        // later, once the container is provisioned, with no code change.
        if loadError != nil, !inMemory {
            print("[Persistence] CloudKit store load failed: \(loadError!). Falling back to local-only store.")
            description.cloudKitContainerOptions = nil
            loadError = nil
            container.loadPersistentStores { _, error in
                if let error = error as NSError? { loadError = error }
            }
        }

        if let loadError {
            print("[Persistence] Core Data store load error: \(loadError), \(loadError.userInfo)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Pin the view context to the current query generation so CloudKit
        // merges don't pull rows out from under active fetched-results views.
        try? container.viewContext.setQueryGenerationFrom(.current)

        // CloudKit sync does NOT carry Core Data default values, so a synced
        // Goal can arrive with status == nil/"". The whole app treats nil as
        // .active (Goal.statusEnum), but raw `status == "active"` predicates
        // (Home, Focus, mentor, widgets, notifications) would skip it — which is
        // why Home showed "no active goal" while the Goals tab still listed it.
        // Normalize those rows to "active" once so every predicate agrees.
        if !inMemory { normalizeGoalStatuses() }
    }

    /// Set any goal whose persisted status is nil/empty to "active" so SQL
    /// predicates match what `Goal.statusEnum` already resolves in memory.
    private func normalizeGoalStatuses() {
        let ctx = container.viewContext
        ctx.perform {
            let req = NSFetchRequest<NSManagedObject>(entityName: "Goal")
            req.predicate = NSPredicate(format: "status == nil OR status == %@", "")
            guard let rows = try? ctx.fetch(req), !rows.isEmpty else { return }
            for row in rows { row.setValue(GoalStatus.active.rawValue, forKey: "status") }
            try? ctx.save()
        }
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            try? context.save()
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Sign-out wipe

    /// Nuke ALL user-scoped data from the device:
    /// • deletes every row from every Core Data entity (goals, pulses, mentor messages, photos, etc.)
    /// • removes every user-keyed UserDefaults entry (transformation photos, meal logs, widgets, prefs)
    /// • clears the App Group store the widgets read from
    ///
    /// DESTRUCTIVE — only for explicit Delete Account (Apple 5.1.1(v) / GDPR).
    /// This batch-deletes every row; because the store is mirrored to the user's
    /// PRIVATE iCloud DB, the deletes ALSO propagate to CloudKit (intended here —
    /// we want a true erasure). NEVER call this from sign-out: that would delete
    /// the user's goals/workouts from iCloud permanently. Sign-out uses
    /// `resetLocalSessionState()` instead.
    func destroyAllUserDataForAccountDeletion() {
        let context = container.viewContext
        let coordinator = container.persistentStoreCoordinator

        // 1) Find every entity in the model and batch-delete its rows.
        let model = container.managedObjectModel
        let entityNames = model.entities.compactMap { $0.name }
        for entityName in entityNames {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let delete = NSBatchDeleteRequest(fetchRequest: fetch)
            delete.resultType = .resultTypeObjectIDs
            do {
                let result = try coordinator.execute(delete, with: context) as? NSBatchDeleteResult
                // Merge deletions into the live viewContext so @FetchRequest refires.
                if let ids = result?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                        into: [context]
                    )
                }
            } catch {
                print("[Wipe] Failed batch delete for \(entityName): \(error)")
            }
        }

        // 2) Drop any still-resident managed objects from the context.
        context.reset()

        // 3) Strip user-scoped UserDefaults keys (standard + App Group).
        UserDataReset.purge()

        // 4) Cancel EVERY pending/delivered local notification. Goals are gone;
        //    otherwise this account's checkin-/evening- and the global goal-named
        //    repeats keep firing for whoever signs in next. Remove ALL (not just
        //    goal ids) because the enabled flag was just purged, so a later
        //    refresh() would run disabled and clear nothing.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Sign-out: drop the in-memory session view + device-local caches ONLY.
    /// Must NOT issue persistent deletes — the store is CloudKit-mirrored, so an
    /// NSBatchDeleteRequest here would also erase the user's private iCloud copy
    /// (the bug that deleted a user's workout on sign-out). On the next sign-in
    /// CloudKit re-hydrates from the intact private DB.
    func resetLocalSessionState() {
        // Detach all managed objects so any @FetchRequest bound to the
        // viewContext re-renders empty until the user signs back in. The rows
        // remain safely on disk + in iCloud.
        container.viewContext.reset()
        // Clear only non-CloudKit, device-local caches (UserDefaults / App Group
        // widget store). These are NOT mirrored to iCloud, so clearing them is
        // safe and keeps the previous account's local cache from leaking.
        UserDataReset.purge()
        // Cancel local notifications scheduled for the signed-out session.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    #if targetEnvironment(simulator)
    /// Seed a test goal in the simulator and let the AI generate the actual pulses.
    /// Idempotent — only seeds if no goals exist. Pulses come from Groq based on
    /// the user's motivation, time-per-day, skill level, and deadline.
    func seedSimulatorGoalIfNeeded() {
        let ctx = container.viewContext

        // Already has goals? Skip.
        let req: NSFetchRequest<Goal> = Goal.fetchRequest()
        if (try? ctx.count(for: req)) ?? 0 > 0 { return }

        // Profile
        let profile = UserProfile.fetchOrCreate(in: ctx)
        if profile.displayName?.isEmpty != false { profile.displayName = "Alex" }
        if profile.mentorPersonality?.isEmpty != false { profile.mentorPersonality = "coach" }
        profile.currentStreak = 5
        profile.longestStreak = 12
        profile.totalXP = 320
        profile.currentLevel = 4
        profile.lastActiveDate = Date()
        profile.onboardingCompleted = true
        profile.onboardingTourCompleted = true

        // Goal: Run a 5K in 30 days — these are the user's inputs.
        // The AI will generate the actual pulses from these.
        let goal = Goal(context: ctx)
        goal.id = UUID()
        goal.title = "Run a 5K in 30 days"
        goal.goalDescription = "Build aerobic base and complete a 5K run"
        goal.category = GoalCategory.fitness.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.deadline = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        goal.createdAt = Date()
        goal.motivationLevel = 8                       // High motivation
        goal.skillLevel = SkillLevel.beginner.rawValue
        goal.availableTimePerDay = 30                  // 30 min/day
        goal.userProfile = profile

        // Seed 7 fallback pulses immediately so the dashboard has data to render
        // even before (or instead of) AI generation completing. The AI will
        // replace these once it returns; until then the user can test the full
        // flow with realistic-looking pulses.
        let fallbackPulses: [(String, String, Int16)] = [
            ("Walk 20 minutes", "Easy pace. Track it with a free run-tracking app.", 20),
            ("Jog/walk intervals — 1 min jog, 2 min walk x 6", "Warm up 3 min. Then alternate. Cool down 3 min.", 25),
            ("Easy 1 km continuous jog", "Slow, conversational pace. If you can't speak, slow down.", 20),
            ("Bodyweight strength — squats, lunges, push-ups", "3 sets of 10 each. Rest 60s between.", 20),
            ("Jog 1.5 km without stopping", "Steady pace. Focus on breathing rhythm.", 25),
            ("Recovery walk + hip mobility", "20 min easy walk + 10 min stretching.", 30),
            ("5K test run — race day", "Pick your route. Pace yourself. Finish strong.", 35)
        ]
        for (i, (title, howTo, mins)) in fallbackPulses.enumerated() {
            let task = DailyTask(context: ctx)
            task.id = UUID()
            task.title = title
            task.taskDescription = howTo
            task.howToDescription = howTo
            task.proofType = "text"
            task.proofDescription = "How did it go? Distance, time, or notes."
            task.stepNumber = Int16(i + 1)
            task.sortOrder = Int16(i)
            task.estimatedMinutes = mins
            task.scheduledDate = Calendar.current.date(byAdding: .day, value: i, to: Date())
            task.xpReward = 10
            task.verificationStatus = "pending"
            task.isCompleted = false
            task.goal = goal
        }

        try? ctx.save()

        // Kick off AI roadmap generation in the background. If it succeeds, it
        // wipes the fallback pulses and replaces them with the AI-generated set.
        let goalID = goal.objectID
        Task.detached(priority: .userInitiated) {
            await AIPulseGenerator.shared.generatePulses(forGoalWithID: goalID)
        }
    }
    #endif
}

// MARK: - User-scoped UserDefaults / App Group purge

enum UserDataReset {
    /// All UserDefaults keys that carry user-specific data. Anything not in this
    /// list (e.g. selected language, terms acceptance) is preserved.
    static let userScopedFixedKeys: [String] = [
        "pulse_enabled_widgets",
        "pulse_widgets_initialized",
        "pulse_pending_goal_flavor",
        "pulse_pending_money_style",
        "pulse_profile_visibility",
        "pulse_is_pro",
        "subscription_tier",
        "pulse_notifications_enabled"
    ]

    /// Prefixes for dynamic user-scoped keys (one entry per goal / per day).
    static let userScopedKeyPrefixes: [String] = [
        "transformation_current_",
        "transformation_goal_",
        "transformation_current_url_",
        "transformation_goal_url_",
        "pulse_meals_",            // MealLogService daily keys
        "pulse_spend_",            // AI spend tracker per-user-per-day
        "pulse_streak_"            // Cached streak by user
    ]

    static func purge() {
        purge(in: UserDefaults.standard)
        if let group = UserDefaults(suiteName: "group.com.shimondeitel.pulsegoals") {
            purge(in: group)
        }
    }

    private static func purge(in defaults: UserDefaults) {
        for key in userScopedFixedKeys {
            defaults.removeObject(forKey: key)
        }
        let snapshot = defaults.dictionaryRepresentation()
        for key in snapshot.keys {
            if userScopedKeyPrefixes.contains(where: { key.hasPrefix($0) }) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
