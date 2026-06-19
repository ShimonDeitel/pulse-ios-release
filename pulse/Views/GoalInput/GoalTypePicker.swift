import SwiftUI
import CoreData

// MARK: - Goal type taxonomy

enum GoalType: String, CaseIterable, Identifiable {
    case money         = "money"
    case transformation = "transformation"
    case workout       = "workout"
    case skill         = "skill"
    case project       = "project"
    case habit         = "habit"
    case challenge     = "challenge"
    case standard      = "standard"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .money:          return "Make Money"
        case .transformation: return "Transformation"
        case .workout:        return "Custom Workout"
        case .skill:          return "Master a Skill"
        case .project:        return "Big Project"
        case .habit:          return "Daily Habit"
        case .challenge:      return "Challenge"
        case .standard:       return "Anything Else"
        }
    }

    var subtitle: String {
        switch self {
        case .money:          return "Earn a target amount via freelance, content, e-com, SaaS, and more"
        case .transformation: return "Upload a before + after photo — AI builds a workout + meal plan"
        case .workout:        return "Pick exercises into training days — auto rep-counting, no AI, no photos"
        case .skill:          return "Learn or master something — Photoshop, Spanish, guitar, anything"
        case .project:        return "Long-term work like finishing college, writing a book, launching a business"
        case .habit:          return "Build a daily habit with streak tracking and accountability"
        case .challenge:      return "Short-term sprint — 7, 14, or 30 day intensive push"
        case .standard:       return "Tell us what you want and we'll figure out the roadmap"
        }
    }

    var iconName: String {
        switch self {
        case .money:          return "dollarsign.circle.fill"
        case .transformation: return "arrow.triangle.2.circlepath.camera.fill"
        case .workout:        return "figure.strengthtraining.traditional"
        case .skill:          return "graduationcap.fill"
        case .project:        return "books.vertical.fill"
        case .habit:          return "repeat.circle.fill"
        case .challenge:      return "flame.fill"
        case .standard:       return "target"
        }
    }

    /// The two no-AI goal types that are free for EVERYONE, regardless of tier:
    /// "Anything Else" (write-your-own steps) and "Custom Workout" (built-in
    /// library + on-device rep counting). They never touch the AI budget — so
    /// they carry a "FREE" badge in the picker.
    var isAlwaysFree: Bool { self == .standard || self == .workout }
}

/// Sub-styles for "Make Money" — referenced by `MakeMoneyGoalView` directly.
/// Kept here so the picker file is the single home of the goal-type taxonomy.
enum MoneyStyle: String, CaseIterable, Identifiable {
    case freelance, content, ecom, dropshipping, saas, trading
    case consulting, realEstate, agency, app, affiliate, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freelance:    return "Freelancing"
        case .content:      return "Content creation"
        case .ecom:         return "E-commerce"
        case .dropshipping: return "Dropshipping"
        case .saas:         return "SaaS / software"
        case .trading:      return "Trading / investing"
        case .consulting:   return "Consulting"
        case .realEstate:   return "Real estate"
        case .agency:       return "Agency"
        case .app:          return "Building an app"
        case .affiliate:    return "Affiliate marketing"
        case .other:        return "Something else"
        }
    }

    var icon: String {
        switch self {
        case .freelance:    return "briefcase.fill"
        case .content:      return "video.fill"
        case .ecom:         return "bag.fill"
        case .dropshipping: return "shippingbox.fill"
        case .saas:         return "macwindow"
        case .trading:      return "chart.line.uptrend.xyaxis"
        case .consulting:   return "person.crop.rectangle.fill"
        case .realEstate:   return "house.fill"
        case .agency:       return "person.3.fill"
        case .app:          return "apps.iphone"
        case .affiliate:    return "link"
        case .other:        return "ellipsis.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .freelance:    return "Sell your skills directly — design, dev, writing, video, etc."
        case .content:      return "YouTube, TikTok, Instagram, podcasting, newsletters"
        case .ecom:         return "Selling physical products you own or make"
        case .dropshipping: return "Selling products you don't hold — supplier ships direct"
        case .saas:         return "Subscription software product you build and own"
        case .trading:      return "Stocks, crypto, options, forex"
        case .consulting:   return "Paid expertise, retainers, advisory"
        case .realEstate:   return "Rentals, flips, wholesaling"
        case .agency:       return "Done-for-you service business with a team"
        case .app:          return "Mobile apps you ship and monetize"
        case .affiliate:    return "Promote other people's products for commission"
        case .other:        return "Tell us in the title, the AI will adapt"
        }
    }
}

// MARK: - Picker (pure router)
//
// Each row sets exactly ONE AppState flag, then dismisses. Sheet wiring lives
// in PulseApp so views can be added/removed without touching this file.
//
// To add a new goal type:
//   1. Add a case to GoalType + the three display getters above.
//   2. Add a `showing<Name>` flag to AppState.
//   3. Map the case to that flag in `route(for:)` below.
//   4. Wire the .sheet in PulseApp with the new dedicated view.
struct GoalTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var viewContext

    /// The type the user tapped, awaiting the reality-check disclaimer. Set this
    /// (rather than routing immediately) so EVERY goal passes through the
    /// honest-odds + not-advice gate before its creation form opens.
    @State private var pendingType: GoalType?
    @State private var showingUpgrade = false

    /// All goals — used only to count how many are currently ACTIVE. Free is
    /// capped at 1 active goal at a time; finishing or deleting a goal frees the
    /// slot so a new one can be created.
    @FetchRequest(sortDescriptors: []) private var allGoals: FetchedResults<Goal>
    private var activeGoalCount: Int { allGoals.filter { $0.statusEnum == .active }.count }

    /// AI is free for everyone now, so goal TYPES are never locked by AI. The
    /// only lock is the free goal cap: a Free user who already has an active
    /// goal must upgrade (or finish/delete it) before starting another.
    private var atGoalCap: Bool {
        !SubscriptionManager.shared.canCreateGoal(currentCount: activeGoalCount)
    }

    /// At the cap, EVERY type opens the paywall; otherwise nothing is locked.
    /// (The limit is on goal COUNT now, not on which type uses AI.)
    private func isLocked(_ type: GoalType) -> Bool { atGoalCap }

    /// Free (unlocked) goal types FIRST, then the Pro-locked ones — so a Free
    /// user sees what they can actually use at the top. Order within each group
    /// is the natural enum order. For a Pro user nothing is locked, so this is
    /// just the enum order (unchanged).
    private var orderedTypes: [GoalType] {
        // Big Project, Daily Habit, and Challenge are retired — no longer offered
        // for creation. (Any existing goals of these types still open and work.)
        let retired: Set<GoalType> = [.project, .habit, .challenge]
        let all = GoalType.allCases.filter { !retired.contains($0) }
        return all.filter { !isLocked($0) } + all.filter { isLocked($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerBlock
                    if !SubscriptionManager.shared.isPro { freeBanner }
                    VStack(spacing: PulseSpacing.md) {
                        ForEach(orderedTypes) { type in
                            GoalTypeRow(type: type, locked: isLocked(type)) {
                                PulseHaptics.medium()
                                // Only a genuinely Pro (AI-built) type opens the
                                // paywall. The always-free manual types create a
                                // goal directly — no cap, no upsell.
                                if isLocked(type) {
                                    showingUpgrade = true
                                } else {
                                    pendingType = type
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PulseSpacing.screenEdge)
                    .padding(.bottom, PulseSpacing.xl)
                }
            }
            .pulseScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .fullScreenCover(item: $pendingType) { type in
                GoalRealityCheckView(
                    goalType: type,
                    onContinue: {
                        pendingType = nil
                        route(for: type)
                    },
                    onCancel: { pendingType = nil }
                )
            }
            .sheet(isPresented: $showingUpgrade) { UpgradeView() }
        }
    }

    /// Explains the free model: build a goal + your own steps now; AI plans
    /// unlock with Pro.
    private var freeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: atGoalCap ? "lock.fill" : "wand.and.stars")
                .font(.system(size: 16))
                .foregroundColor(PulseColors.gold)
            Text(atGoalCap
                 ? "You're on Free — 1 goal at a time. Finish or delete your current goal to start a new one, or upgrade to Pulse Pro for unlimited goals."
                 : "You're on Free: the full AI coach plus 1 active goal. Upgrade to Pulse Pro any time for unlimited goals and Primary Access — priority, no waiting.")
                .font(.system(size: 12.5))
                .foregroundColor(PulseColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.gold.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PulseColors.gold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.bottom, PulseSpacing.md)
    }

    private var headerBlock: some View {
        VStack(spacing: PulseSpacing.sm) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(PulseColors.signal)
            Text("New Pulse")
                .font(PulseTypography.headlineLarge)
                .foregroundColor(PulseColors.textPrimary)
                .headlineTracking()
            Text("What type of goal do you want to create?")
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.textSecondary)
        }
        .padding(.top, PulseSpacing.xl)
        .padding(.bottom, PulseSpacing.xl)
    }

    /// Maps a GoalType to its dedicated AppState flag. Dismiss first so the
    /// destination sheet can present cleanly from the root.
    private func route(for type: GoalType) {
        // Remember that a goal of this type was started — if the user bails out
        // of the creation flow without saving, it shows up under Drafts in the
        // Goals tab. Auto-clears once they actually create the goal.
        DraftService.shared.start(type)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Clear any legacy "pending flavor" hint — dedicated views own
            // their own state now, no out-of-band UserDefaults stash needed.
            UserDefaults.standard.removeObject(forKey: "pulse_pending_goal_flavor")
            UserDefaults.standard.removeObject(forKey: "pulse_pending_money_style")

            switch type {
            case .money:          appState.showingMakeMoney = true
            case .transformation: appState.showingPhotoTransformation = true
            case .workout:        appState.showingWorkoutBuilder = true
            case .skill:          appState.showingMasterSkill = true
            case .project:        appState.showingBigProject = true
            case .habit:          appState.showingDailyHabit = true
            case .challenge:      appState.showingChallenge = true
            case .standard:       appState.showingGoalInput = true
            }
        }
    }
}

// MARK: - Row component

private struct GoalTypeRow: View {
    let type: GoalType
    var locked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PulseSpacing.lg) {
                Image(systemName: type.iconName)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(locked ? PulseColors.muted : PulseColors.signal)
                    .frame(width: 48, height: 48)
                    .background((locked ? PulseColors.muted : PulseColors.signal).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: M3Shapes.medium, style: .continuous))

                VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                    Text(type.displayName)
                        .font(PulseTypography.titleMedium)
                        .foregroundColor(PulseColors.textPrimary)
                    Text(type.subtitle)
                        .font(PulseTypography.bodySmall)
                        .foregroundColor(PulseColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if locked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                    }
                    .foregroundColor(PulseColors.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PulseColors.gold.opacity(0.12))
                    .clipShape(Capsule())
                } else if type.isAlwaysFree {
                    // Always-free, no-AI goal types (Custom Workout, Anything Else)
                    // carry a green FREE badge so it's clear they never cost AI.
                    Text("FREE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(PulseColors.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PulseColors.green.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PulseColors.textTertiary)
                }
            }
            .padding(PulseSpacing.cardPadding)
            .background(PulseColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
            )
            .opacity(locked ? 0.85 : 1)
        }
        .buttonStyle(.plain)
    }
}
