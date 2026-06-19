import SwiftUI
import CoreData

@Observable
class AppState {
    // Default tab is Home. In SIMULATOR builds only, an optional `pulse_debug_tab`
    // UserDefault lets tooling open a specific tab on launch (used to capture
    // per-tab marketing screenshots). No effect on real-device builds.
    var selectedTab: Int = {
        #if targetEnvironment(simulator)
        if let t = UserDefaults.standard.object(forKey: "pulse_debug_tab") as? Int { return t }
        #endif
        return 0
    }()
    // Read SYNCHRONOUSLY from UserDefaults + AuthManager so the first
    // render of RootView already knows whether to show OnboardingFlow,
    // AuthWelcomeView, or the main app. Without this the user sees the
    // OnboardingFlow flash on every cold launch while Core Data loads.
    var isAuthenticated: Bool = AuthManager.shared.isAuthenticated
    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "pulse_onboarding_complete")
    var showOnboardingTour: Bool = false
    /// Set when the user is signed in but we have no real display name yet
    /// (Apple only returns the name on first authorization). The main tab view
    /// presents a one-field prompt so the profile never gets stuck on "User".
    var needsNameEntry: Bool = false
    var activeGoal: Goal? = nil
    var showingFocusMode: Bool = false
    var showingProgress: Bool = false
    /// One-shot flag: set true on a real Pro purchase/redeem to play the
    /// "Welcome to Pro" celebration overlay (rendered at the app root).
    var showWelcomeToPro: Bool = false
    var showingGoalInput: Bool = false
    var showingGoalTypePicker: Bool = false
    var showingCelebration: Bool = false

    // Per-goal-type dedicated entry points. Each routes to its OWN view
    // file with type-specific inputs — no shared wizard.
    var showingPhotoTransformation: Bool = false
    var showingMakeMoney: Bool = false
    var showingMasterSkill: Bool = false
    var showingBigProject: Bool = false
    var showingChallenge: Bool = false
    var showingDailyHabit: Bool = false
    /// No-AI, no-photo manual workout builder (free + pro).
    var showingWorkoutBuilder: Bool = false

    // Pulse-completion celebration overlay state.
    // Set via celebratePulseCompletion(...) — the root view renders the overlay.
    var celebrationData: PulseCelebrationData? = nil

    /// Fire the celebration after a pulse is marked complete. XP, level, streak,
    /// persistence, and the home-screen widget are ALL credited through the ONE
    /// canonical path — `UserProfile.registerCompletion` — so completing from any
    /// screen yields the exact same result; this method just layers the overlay
    /// on top. Pass the pulse's real reward as `xpReward` (`Int(task.xpReward)`).
    /// Callers must NOT also mutate `totalXP` themselves (that was the source of
    /// the 0/10/15/25 divergence).
    func celebratePulseCompletion(
        pulseNumber: Int,
        nextPulseTitle: String?,
        profile: UserProfile?,
        goalTitle: String? = nil,
        xpReward: Int = 10,
        in context: NSManagedObjectContext
    ) {
        let oldLevel = Int(profile?.currentLevel ?? 1)
        profile?.registerCompletion(xp: xpReward, in: context)
        let newXP = Int(profile?.totalXP ?? 0)
        let newLevel = Int(profile?.currentLevel ?? 1)
        let didLevelUp = newLevel > oldLevel

        let authorName = (profile?.displayNameValue.isEmpty == false ? profile?.displayNameValue : nil) ?? "You"
        let authorId = AuthManager.shared.currentUser?.userId ?? profile?.id?.uuidString ?? "me"

        celebrationData = PulseCelebrationData(
            pulseNumber: pulseNumber,
            xpGained: xpReward,
            totalXP: newXP,
            nextPulseTitle: nextPulseTitle,
            didLevelUp: didLevelUp,
            newLevel: newLevel,
            goalTitle: goalTitle,
            authorId: authorId,
            authorName: authorName
        )
    }

    // MARK: - Goal completion celebration

    /// Full-screen celebration shown when an ENTIRE goal is finished.
    var goalCompletionData: GoalCompletionData? = nil

    func celebrateGoalCompletion(goalTitle: String, daysTaken: Int, totalPulses: Int, isFirst: Bool) {
        goalCompletionData = GoalCompletionData(
            goalTitle: goalTitle, daysTaken: daysTaken, totalPulses: totalPulses, isFirst: isFirst
        )
    }

    func checkOnboardingStatus(context: NSManagedObjectContext) {
        let profile = UserProfile.fetchOrCreate(in: context)
        // Keep the synchronous default but reconcile with Core Data too —
        // older installs that completed onboarding before the UserDefaults
        // flag existed will still skip onboarding correctly.
        if profile.onboardingCompleted {
            isOnboardingComplete = true
            UserDefaults.standard.set(true, forKey: "pulse_onboarding_complete")
        }

        // Authentication is driven SOLELY by a real, Keychain-backed Sign in with
        // Apple session (AuthManager). NEVER infer "signed in" from onboarding
        // state — seeing the intro slides is not an account. (The old
        // `else if isOnboardingComplete { isAuthenticated = true }` fallback
        // silently skipped the "Continue with Apple" gate on relaunch; removed.)
        let authManager = AuthManager.shared
        isAuthenticated = authManager.isAuthenticated

        #if targetEnvironment(simulator)
        // Simulator: seed a test goal so the dashboard has data once signed in.
        // The Sign in with Apple gate is REAL here too by default (matches the
        // device), so it can actually be tested. For fast UI iteration WITHOUT
        // going through Apple sign-in on the simulator, set the debug flag:
        //   xcrun simctl spawn booted defaults write com.shimondeitel.pulse pulse_debug_skip_auth -bool YES
        if !isAuthenticated, UserDefaults.standard.bool(forKey: "pulse_debug_skip_auth") {
            isAuthenticated = true
            isOnboardingComplete = true
            profile.onboardingCompleted = true
            profile.onboardingTourCompleted = true
            if profile.authProvider == nil { profile.authProvider = "apple" }
            try? context.save()
        }
        PersistenceController.shared.seedSimulatorGoalIfNeeded()
        #endif

        // If authenticated but hasn't done the feature tour yet
        if isAuthenticated && isOnboardingComplete && !profile.onboardingTourCompleted {
            showOnboardingTour = true
        }

        // No name prompt: the name comes from Sign in with Apple on first
        // authorization (or a sensible fallback). We never interrupt the user
        // with a "what should we call you?" sheet.
        needsNameEntry = false

        // Silent entitlement reconciliation on launch — reads the verified
        // current entitlement WITHOUT prompting for the Apple Account. The
        // prompting `restore()` is reserved for the explicit "Restore" button.
        SubscriptionManager.shared.bootstrap()
    }
}

struct PulseCelebrationData: Identifiable {
    let id = UUID()
    let pulseNumber: Int
    let xpGained: Int
    let totalXP: Int
    let nextPulseTitle: String?
    let didLevelUp: Bool
    let newLevel: Int
    var goalTitle: String? = nil
    var authorId: String = "me"
    var authorName: String = "You"
}

struct GoalCompletionData: Identifiable {
    let id = UUID()
    let goalTitle: String
    let daysTaken: Int
    let totalPulses: Int
    let isFirst: Bool
}
