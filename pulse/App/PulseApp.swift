import SwiftUI
import UIKit
import CoreData
import UserNotifications
import WidgetKit

@main
struct PulseApp: App {
    let persistenceController = PersistenceController.shared
    @State private var appState = AppState()
    @State private var localization = LocalizationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pulse_color_scheme") private var colorSchemePreference: String = "system"

    /// Pull any pulse completions queued by the interactive widget into Core Data.
    /// `syncPendingWidgetCompletions` itself credits each completion through the
    /// canonical `registerCompletion` path (XP, level, streak, widget refresh), so
    /// this background sync must NOT also call `celebratePulseCompletion` — doing
    /// so would award the XP a second time. Widget completions get no in-app
    /// overlay; the overlay is reserved for completions made inside the app.
    private func syncWidgetCompletions() {
        let ctx = persistenceController.container.viewContext
        WidgetDataService.shared.syncPendingWidgetCompletions(context: ctx)
        // No explicit cloud push needed: NSPersistentCloudKitContainer mirrors
        // these completions to the user's private iCloud DB automatically.
    }

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(appState)
                .environment(localization)
                .preferredColorScheme(resolvedColorScheme)
                // CRITICAL: Force full re-render when language changes so every
                // .localized string is re-evaluated. The .id() modifier makes SwiftUI
                // tear down and recreate the view tree whenever revision changes.
                .id(localization.revision)
                .onAppear {
                    LocalizationManager.shared.loadCachedTranslations()
                    // Self-heal any goal whose steps are all done but was left
                    // ACTIVE by an older completion path — otherwise its daily
                    // "How did your pulse go? log it" reminder keeps firing.
                    // Runs BEFORE refresh so the rebuilt schedule excludes it.
                    AdaptiveNotificationScheduler.migrateStrandedCompletedGoals()
                    // NOTE: chat history is no longer purged — each goal now has its
                    // own PRIVATE chat room whose conversation persists (Core Data,
                    // mirrored to the user's private iCloud). See MentorChatView.
                    // AI-driven adaptive notifications — user only toggles on/off.
                    let notificationsEnabled = UserDefaults.standard.object(forKey: "pulse_notifications_enabled") as? Bool ?? true
                    AdaptiveNotificationScheduler.shared.refresh(enabled: notificationsEnabled)
                    // Purge reminders for goals deleted before the cancel-on-delete fix.
                    AdaptiveNotificationScheduler.reconcileOrphanedGoalNotifications()
                    // Sync any pulse completions tapped from the home-screen widget
                    syncWidgetCompletions()
                    // Update home screen widgets
                    WidgetDataService.shared.updateWidgets(context: persistenceController.container.viewContext)
                    // Private data syncs to iCloud automatically via CloudKit.
                    // Keep the screen awake the whole time the app is open. The user
                    // is often watching a Live workout / reading a pulse without
                    // touching the screen, so the auto-lock must never kick in while
                    // we're foregrounded. Restored on background (below) so we don't
                    // hold the screen on after the user leaves.
                    UIApplication.shared.isIdleTimerDisabled = true
                    // Install the app-wide "tap anywhere to dismiss the keyboard"
                    // recognizer. Deferred so the key window definitely exists.
                    DispatchQueue.main.async { KeyboardDismissInstaller.shared.installInAllWindows() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Hold the screen awake while active; release it when the app is
                    // backgrounded or inactive so we never drain battery off-screen.
                    UIApplication.shared.isIdleTimerDisabled = (newPhase == .active)
                    if newPhase == .active {
                        syncWidgetCompletions()
                        // Reconcile Pro state on every foreground so a subscription
                        // cancelled/resumed in Settings.app (which never routes
                        // through StoreKit's in-app listener) is picked up here.
                        Task { await StoreManager.shared.refreshEntitlements() }
                        // Always push fresh widget data on foreground, even when no
                        // widget completions were pending to sync above.
                        WidgetDataService.shared.updateWidgets(context: persistenceController.container.viewContext)
                        // Re-derive today's meal log: if the app was left open across
                        // midnight, this rolls the in-memory entries over to the new day.
                        MealLogService.shared.load()
                        // Re-evaluate goal-aware notifications on every foreground so
                        // the set self-corrects after goals are created/deleted/
                        // completed (last goal gone -> show the start-a-goal nudge;
                        // first goal added -> drop it; completed goal -> stop its
                        // per-goal reminders).
                        AdaptiveNotificationScheduler.migrateStrandedCompletedGoals()
                        AdaptiveNotificationScheduler.shared.refreshFromSettings()
                        AdaptiveNotificationScheduler.reconcileOrphanedGoalNotifications()
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @State private var importedQuoteConfirmation = false

    var body: some View {
        ZStack {
            Group {
                if !appState.isOnboardingComplete {
                    // First launch -> show onboarding intro slides
                    OnboardingFlow()
                } else if !appState.isAuthenticated {
                    // Onboarding seen but not logged in -> show auth
                    AuthWelcomeView()
                } else if appState.showOnboardingTour {
                    // Authenticated but first time -> show interactive tour
                    OnboardingTourView()
                } else if !StoreManager.shared.hasResolvedEntitlements {
                    // Delay showing main app until StoreKit finishes its first
                    // entitlement resolution — prevents a flash of "Free" state
                    // for Pro subscribers on launch.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    // Fully onboarded -> main app
                    MainTabView()
                }
            }
            .animation(.smooth(duration: 0.4), value: appState.isAuthenticated)
            .animation(.smooth(duration: 0.4), value: appState.isOnboardingComplete)
            .animation(.smooth(duration: 0.4), value: appState.showOnboardingTour)

            // Pulse-completion celebration overlay — sits above EVERYTHING
            // so it triggers no matter which screen marks the pulse done.
            if let data = appState.celebrationData {
                PulseCompletionCelebration(
                    pulseNumber: data.pulseNumber,
                    xpGained: data.xpGained,
                    totalXP: data.totalXP,
                    nextPulseTitle: data.nextPulseTitle,
                    didLevelUp: data.didLevelUp,
                    newLevel: data.newLevel,
                    goalTitle: data.goalTitle,
                    authorId: data.authorId,
                    authorName: data.authorName,
                    onDismiss: { appState.celebrationData = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(999)
            }

            // Whole-goal completion celebration — sits above the pulse one.
            if let g = appState.goalCompletionData {
                GoalCompletionCelebration(
                    goalTitle: g.goalTitle,
                    daysTaken: g.daysTaken,
                    totalPulses: g.totalPulses,
                    isFirst: g.isFirst,
                    onDismiss: { appState.goalCompletionData = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)
            }

            // Welcome-to-Pro celebration — fired once on a real purchase/redeem.
            if appState.showWelcomeToPro {
                WelcomeToProView { appState.showWelcomeToPro = false }
                    .transition(.opacity)
                    .zIndex(1001)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.showWelcomeToPro)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: appState.celebrationData?.id)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: appState.goalCompletionData?.id)
        .onAppear {
            appState.checkOnboardingStatus(context: viewContext)
        }
        // Honor an auth state change DURING the session. AuthManager owns the
        // real session and posts these; AppState.isAuthenticated is a separate
        // copy the UI gates on, so bridge it here. Critically this covers the
        // auto-revocation path (credential .revoked/.notFound -> signOut), which
        // otherwise left a revoked user inside the app until the next launch.
        .onReceive(NotificationCenter.default.publisher(for: .pulseUserDidSignOut)) { _ in
            appState.isAuthenticated = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulseUserDidSignIn)) { _ in
            appState.isAuthenticated = true
        }
        // Shared "quote note" deep link (pulse://quote?q=…) → save it to THIS
        // user's own Saved Quotes, then confirm.
        .onOpenURL { url in
            guard let quote = QuoteShare.decode(url) else { return }
            SocialStore.shared.saveQuote(quote)
            PulseHaptics.success()
            importedQuoteConfirmation = true
        }
        .alert("Quote saved", isPresented: $importedQuoteConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Added to your Saved Quotes — find it in Profile \u{203A} Saved Quotes.")
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        @Bindable var state = appState
        let _ = LocalizationManager.shared.revision // trigger re-render on language change
        TabView(selection: $state.selectedTab) {
            Tab("Home".localized, systemImage: "square.grid.2x2.fill", value: 0) {
                NavigationStack {
                    DashboardView()
                }
            }

            Tab("Goals".localized, systemImage: "target", value: 1) {
                NavigationStack {
                    GoalsListView()
                }
            }

            Tab("Chat".localized, systemImage: "bubble.left.and.bubble.right.fill", value: 2) {
                NavigationStack {
                    MentorChatView()
                }
            }

            Tab("Profile".localized, systemImage: "person.crop.circle.fill", value: 3) {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(PulseColors.primary)
        // iOS 26: collapse the tab bar when scrolling down in any tab, and
        // bring it back on scroll up. No-op on iOS 18–25.
        .pulseTabBarMinimizeOnScroll()
        .sheet(isPresented: $state.showingGoalTypePicker) {
            GoalTypePicker()
        }
        // "Anything Else" — the only flow that still uses the multi-step wizard.
        .sheet(isPresented: $state.showingGoalInput) {
            GoalInputFlowView()
                .onAppear { DraftService.shared.start(.standard) }
        }
        // Dedicated, type-specific entry points. Each one its own view file.
        .sheet(isPresented: $state.showingPhotoTransformation) {
            PhotoTransformationView()
                .onAppear { DraftService.shared.start(.transformation) }
        }
        .sheet(isPresented: $state.showingMakeMoney) {
            MakeMoneyGoalView()
                .onAppear { DraftService.shared.start(.money) }
        }
        .sheet(isPresented: $state.showingMasterSkill) {
            MasterSkillGoalView()
                .onAppear { DraftService.shared.start(.skill) }
        }
        .sheet(isPresented: $state.showingBigProject) {
            BigProjectGoalView()
                .onAppear { DraftService.shared.start(.project) }
        }
        .sheet(isPresented: $state.showingChallenge) {
            ChallengeGoalView()
                .onAppear { DraftService.shared.start(.challenge) }
        }
        .sheet(isPresented: $state.showingDailyHabit) {
            DailyHabitGoalView()
                .onAppear { DraftService.shared.start(.habit) }
        }
        // Custom Workout — no-AI, no-photo manual builder (free + pro).
        .sheet(isPresented: $state.showingWorkoutBuilder) {
            WorkoutBuilderView()
                .onAppear { DraftService.shared.start(.workout) }
        }
        // Focus timer — immersive full-screen cover (escapable via ✕).
        .fullScreenCover(isPresented: $state.showingFocusMode) {
            NavigationStack {
                FocusSessionView(goal: state.activeGoal)
            }
        }
        // Progress / momentum dashboard.
        .sheet(isPresented: $state.showingProgress) {
            ProgressInsightsView()
        }
    }
}

private extension View {
    /// iOS 26+: collapse the tab bar when the user scrolls down, and restore it
    /// when they scroll up (native `TabView` behavior). No-op on iOS 18–25 so
    /// the app still builds and runs against the 18.0 deployment target.
    @ViewBuilder
    func pulseTabBarMinimizeOnScroll() -> some View {
        // Compile the iOS 26 API only when building against the iOS 26 SDK (Swift 6.2+/Xcode 26).
        // On an older SDK (cloud CI on a released toolchain) this is a no-op, preserving the
        // iOS 18.0 deployment target.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
