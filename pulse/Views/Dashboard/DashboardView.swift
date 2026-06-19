import SwiftUI
import CoreData

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    // Treat a goal as active when its status is "active" OR nil/empty. CloudKit
    // sync does NOT carry Core Data default values, so a synced goal can arrive
    // with status == nil — the rest of the app coerces that to .active (see
    // Goal.statusEnum), but a raw SQL `status == "active"` predicate would miss
    // it, which is exactly why Home showed "no active goal" while the Goals tab
    // (no predicate) still listed it.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)],
        predicate: NSPredicate(format: "status == %@ OR status == nil OR status == %@",
                               GoalStatus.active.rawValue, ""),
        animation: .default
    )
    private var activeGoals: FetchedResults<Goal>

    /// EVERY goal (no status filter) — the same set the Goals tab shows. Used so
    /// Home never claims "no active goals" while the user still has goals they're
    /// working toward (e.g. a repeating workout plan whose template days are done).
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)],
        animation: .default
    )
    private var allGoals: FetchedResults<Goal>

    @FetchRequest(
        sortDescriptors: [],
        predicate: nil,
        animation: .default
    )
    private var profiles: FetchedResults<UserProfile>

    @State private var showingWidgetEditor = false
    // Shown when a Free user taps a goal that's locked behind Pro (e.g. an
    // AI-built goal after downgrading). Routes to the paywall instead of the
    // goal's detail/complete UI, so paid AI content can't be completed for free.
    @State private var showingUpgrade = false

    private var profile: UserProfile? { profiles.first }

    /// Goals to surface on Home: active ones if any, otherwise fall back to all
    /// goals so a goal the user is still working toward never disappears here.
    private var displayGoals: [Goal] { activeGoals.isEmpty ? Array(allGoals) : Array(activeGoals) }
    private var primaryGoal: Goal? { displayGoals.first }
    private var otherGoals: [Goal] { Array(displayGoals.dropFirst()) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Top Bar ──────────────────────────────
                topBar
                    .padding(.top, PulseSpacing.sm)

                // ── Greeting & Date ─────────────────────
                greetingSection
                    .padding(.top, PulseSpacing.xl)

                // ── Primary Goal Card (dark) ────────────
                if let goal = primaryGoal {
                    if goal.isLockedForCurrentTier {
                        // Locked Pro goal on Free: tapping opens the paywall, not
                        // the goal's detail/complete UI.
                        Button { showingUpgrade = true } label: {
                            primaryGoalCard(goal)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, PulseSpacing.xl)
                    } else {
                        NavigationLink(destination: GoalDetailRouter(goal: goal)) {
                            primaryGoalCard(goal)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, PulseSpacing.xl)
                    }
                }

                // ── Today's Pulses ──────────────────────
                // Hidden for a locked Pro goal — its pulses are paid AI content,
                // so we don't surface tappable rows that lead to completion.
                if let goal = primaryGoal, !goal.isLockedForCurrentTier, !goal.todaysTasks.isEmpty {
                    todaysPulsesSection(goal)
                        .padding(.top, PulseSpacing.xxl)
                }

                // ── Quick Actions ────────────────────────
                QuickActionBar()
                    .padding(.top, PulseSpacing.xxl)

                // ── Other Goals ──────────────────────────
                if !otherGoals.isEmpty {
                    otherGoalsSection
                        .padding(.top, PulseSpacing.xxl)
                }

                // ── Empty State ──────────────────────────
                // Only when there are NO goals at all — never while the user
                // still has a goal in the Goals tab they're working toward.
                if displayGoals.isEmpty {
                    emptyState
                        .padding(.top, PulseSpacing.section)
                }

                // ── Insights ─────────────────────────────
                // Insights / widgets — kept tight per the "no surprise widgets" rule.
                insightsSection
                    .padding(.top, PulseSpacing.xxl)
            }
            .padding(.bottom, PulseSpacing.screenBottom)
        }
        .pulseScreen()
        .navigationBarHidden(true)
        .sheet(isPresented: $showingUpgrade) { UpgradeView() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Pulse logo + text
            HStack(spacing: PulseSpacing.sm) {
                // Mini EKG icon
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PulseColors.signal)
                Text("Pulse Goals")
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundColor(PulseColors.textPrimary)
                    .tracking(-0.3)
            }

            Spacer()

            HStack(spacing: PulseSpacing.sm) {
                // Streak badge — taps to profile (full streak + stats)
                if let profile = profile, profile.currentStreak > 0 {
                    Button {
                        appState.selectedTab = 3
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundColor(PulseColors.signal)
                            Text("\(profile.currentStreak)")
                                .font(PulseTypography.monoCaption)
                                .foregroundColor(PulseColors.textPrimary)
                        }
                        .padding(.horizontal, PulseSpacing.sm + 2)
                        .padding(.vertical, PulseSpacing.xs + 1)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Avatar — shows profile photo if attached, else initial. Taps to profile.
                Button {
                    appState.selectedTab = 3   // Profile tab (Home 0, Goals 1, Chat 2, Profile 3)
                } label: {
                    MyAvatarView(
                        size: 34,
                        initial: String(profile?.displayNameValue.prefix(1) ?? "P").uppercased(),
                        color: PulseColors.textPrimary
                    )
                }
                .accessibilityLabel("Profile")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            // Date eyebrow
            Text(dateEyebrow)
                .font(PulseTypography.eyebrow)
                .foregroundColor(PulseColors.textTertiary)
                .eyebrowTracking()

            // Greeting
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingLine1)
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(PulseColors.textPrimary)
                    .tracking(-0.5)
                Text(greetingLine2)
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(PulseColors.textTertiary)
                    .tracking(-0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var dateEyebrow: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d"
        let base = formatter.string(from: Date()).uppercased()
        if let goal = primaryGoal {
            let total = max(1, Calendar.current.dateComponents([.day], from: goal.createdAt ?? Date(), to: goal.deadline ?? Date()).day ?? 90)
            let elapsed = max(0, Calendar.current.dateComponents([.day], from: goal.createdAt ?? Date(), to: Date()).day ?? 0)
            return "\(base) · DAY \(elapsed) OF \(total)"
        }
        return base
    }

    private var greetingLine1: String {
        let todayCount = primaryGoal?.todaysTasks.filter { !$0.isCompleted }.count ?? 0
        if todayCount == 0 && primaryGoal != nil { return "All clear today,".localized }
        if todayCount == 1 { return "One pulse today,".localized }
        if todayCount > 0 { return "\(todayCount) " + "pulses today,".localized }

        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning,".localized
        case 12..<17: return "Good afternoon,".localized
        case 17..<21: return "Good evening,".localized
        default: return "Good night,".localized
        }
    }

    private var greetingLine2: String {
        let todayCount = primaryGoal?.todaysTasks.filter { !$0.isCompleted }.count ?? 0
        if todayCount == 0 && primaryGoal != nil { return "you're ahead.".localized }
        if todayCount > 0 { return "then you're ahead.".localized }
        return profile?.displayNameValue ?? "start something."
    }

    // MARK: - Primary Goal Card (Dark)

    private func primaryGoalCard(_ goal: Goal) -> some View {
        VStack(spacing: 0) {
            // Top section: title + progress
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: PulseSpacing.xs) {
                    HStack(spacing: PulseSpacing.sm) {
                        Circle()
                            .fill(PulseColors.signal)
                            .frame(width: 7, height: 7)
                        Text("ACTIVE GOAL".localized)
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(.white.opacity(0.5))
                            .eyebrowTracking()
                        if goal.isLockedForCurrentTier {
                            ProLockPill()
                        }
                    }
                    Text(goal.titleValue)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(-0.5)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(goal.progressPercentage * 100))%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("COMPLETE".localized)
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(.white.opacity(0.4))
                        .eyebrowTracking()
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PulseColors.signal)
                        .frame(width: geo.size.width * goal.progressPercentage, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, PulseSpacing.md)

            // Bottom stats
            HStack {
                Text(goal.createdAt.map { shortDate($0) } ?? "START")
                    .font(PulseTypography.eyebrow)
                    .foregroundColor(.white.opacity(0.4))
                    .eyebrowTracking()
                Spacer()
                Text("\(goal.completedSteps)/\(goal.totalSteps) " + "PULSES".localized + " · \(goal.daysRemaining) " + "DAYS LEFT".localized)
                    .font(PulseTypography.eyebrow)
                    .foregroundColor(.white.opacity(0.4))
                    .eyebrowTracking()
                Spacer()
                Text(goal.deadline.map { shortDate($0) } ?? "END")
                    .font(PulseTypography.eyebrow)
                    .foregroundColor(.white.opacity(0.4))
                    .eyebrowTracking()
            }
            .padding(.top, PulseSpacing.sm + 2)
        }
        .padding(PulseSpacing.cardPadding)
        .background(PulseColors.mono)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date).uppercased()
    }

    // MARK: - Today's Pulses

    private func todaysPulsesSection(_ goal: Goal) -> some View {
        VStack(spacing: PulseSpacing.cardGap) {
            HStack {
                Text("Today's pulses".localized)
                    .font(PulseTypography.headlineSmall)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()
                Spacer()
                let done = goal.todaysTasks.filter { $0.isCompleted }.count
                let total = goal.todaysTasks.count
                Text("\(done)/\(total)")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.textTertiary)
            }
            .padding(.horizontal, PulseSpacing.screenEdge)

            VStack(spacing: 0) {
                ForEach(Array(goal.todaysTasks.prefix(5).enumerated()), id: \.element.objectID) { index, task in
                    NavigationLink(destination: GoalDetailRouter(goal: goal)) {
                        todayTaskRow(task, isLast: index == min(goal.todaysTasks.count - 1, 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(PulseColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
            )
            .padding(.horizontal, PulseSpacing.screenEdge)
        }
    }

    private func todayTaskRow(_ task: DailyTask, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: PulseSpacing.md) {
            // Check circle
            ZStack {
                Circle()
                    .stroke(task.isCompleted ? PulseColors.signal : PulseColors.muted2, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                if task.isCompleted {
                    Circle()
                        .fill(PulseColors.mono)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("PULSE \(String(format: "%02d", task.stepNumber))")
                    .font(PulseTypography.eyebrow)
                    .foregroundColor(PulseColors.textTertiary)
                    .eyebrowTracking()
                Text(task.titleValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(task.isCompleted ? PulseColors.textTertiary : PulseColors.textPrimary)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
            }

            Spacer()

            if task.estimatedMinutes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("\(task.estimatedMinutes)m")
                        .font(PulseTypography.monoCaption)
                }
                .foregroundColor(PulseColors.textTertiary)
            }
        }
        .padding(.horizontal, PulseSpacing.cardPadding)
        .padding(.vertical, PulseSpacing.md)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(PulseColors.outlineVariant)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Other Goals

    private var otherGoalsSection: some View {
        VStack(spacing: PulseSpacing.cardGap) {
            HStack {
                Text("Other goals".localized)
                    .font(PulseTypography.headlineSmall)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()
                Spacer()
            }
            .padding(.horizontal, PulseSpacing.screenEdge)

            VStack(spacing: 0) {
                ForEach(Array(otherGoals.enumerated()), id: \.element.objectID) { index, goal in
                    NavigationLink(destination: GoalDetailRouter(goal: goal)) {
                        otherGoalRow(goal, isLast: index == otherGoals.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(PulseColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
            )
            .padding(.horizontal, PulseSpacing.screenEdge)
        }
    }

    private func otherGoalRow(_ goal: Goal, isLast: Bool) -> some View {
        HStack(spacing: PulseSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.titleValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PulseColors.textPrimary)
                    .lineLimit(1)
                Text("\(goal.completedSteps) of \(goal.totalSteps) · \(goal.daysRemaining) " + "days left".localized)
                    .font(.system(size: 12.5))
                    .foregroundColor(PulseColors.textTertiary)
            }
            Spacer()
            // Mini progress indicator
            Text("\(Int(goal.progressPercentage * 100))%")
                .font(PulseTypography.monoCaption)
                .foregroundColor(PulseColors.signal)
        }
        .padding(.horizontal, PulseSpacing.cardPadding)
        .padding(.vertical, PulseSpacing.md)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(PulseColors.outlineVariant)
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: PulseSpacing.xl) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(PulseColors.signal.opacity(0.4))

            VStack(spacing: PulseSpacing.sm) {
                Text("No active goals".localized)
                    .font(PulseTypography.titleLarge)
                    .foregroundColor(PulseColors.textPrimary)
                Text("Set your first goal and let Pulse build\nyour roadmap to achievement.".localized)
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                appState.showingGoalTypePicker = true
            } label: {
                HStack(spacing: PulseSpacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New Goal".localized)
                        .font(PulseTypography.labelLargeEmphasized)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(PulseColors.signal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PulseSpacing.section)
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(spacing: PulseSpacing.cardGap) {
            HStack {
                Text("Insights".localized)
                    .font(PulseTypography.headlineSmall)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()
                Spacer()
                Button {
                    showingWidgetEditor = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                        Text("Edit".localized)
                            .font(PulseTypography.labelSmall)
                    }
                    .foregroundColor(PulseColors.textTertiary)
                }
            }
            .padding(.horizontal, PulseSpacing.screenEdge)

            DynamicWidgetGrid(
                goals: displayGoals,
                profile: profile
            )
        }
        .sheet(isPresented: $showingWidgetEditor) {
            WidgetEditorView(goals: displayGoals, profile: profile)
        }
    }
}

// MARK: - Widget Editor
// Single source of truth: WidgetEngine.realWidgets. The editor only shows
// widgets that have a real, data-backed render — no orphan toggles.

struct WidgetEditorView: View {
    let goals: [Goal]
    let profile: UserProfile?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("pulse_enabled_widgets") private var enabledWidgetsData: Data = Data()

    @State private var enabledSet: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(WidgetEngine.realWidgets, id: \.type.rawValue) { widget in
                        let reason = WidgetEngine.unavailableReason(widget.type, goals: goals, profile: profile)
                        let isAvailable = (reason == nil)
                        HStack(spacing: 12) {
                            Image(systemName: widget.icon)
                                .font(.system(size: 16))
                                .foregroundColor(isAvailable ? PulseColors.signal : PulseColors.muted)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(widget.name.localized)
                                    .font(.system(size: 15))
                                    .foregroundColor(isAvailable ? PulseColors.ink : PulseColors.muted)
                                if let reason {
                                    Text(reason)
                                        .font(.system(size: 11))
                                        .foregroundColor(PulseColors.muted)
                                } else {
                                    Text(sizeLabel(widget.size))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(PulseColors.muted)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { isAvailable && enabledSet.contains(widget.type.rawValue) },
                                set: { enabled in
                                    guard isAvailable else {
                                        PulseHaptics.warning()
                                        return
                                    }
                                    if enabled {
                                        enabledSet.insert(widget.type.rawValue)
                                    } else {
                                        enabledSet.remove(widget.type.rawValue)
                                    }
                                    saveWidgets()
                                    PulseHaptics.light()
                                }
                            ))
                            .tint(PulseColors.signal)
                            .labelsHidden()
                            .disabled(!isAvailable)
                        }
                        .listRowBackground(PulseColors.paper)
                    }
                } header: {
                    Text("\(enabledSet.count) of \(WidgetEngine.realWidgets.count) widgets enabled")
                        .font(PulseTypography.labelSmall)
                        .foregroundColor(PulseColors.muted)
                } footer: {
                    Text("Tap a toggle to show or hide that widget on your dashboard. Changes save instantly.")
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.muted)
                }

                // Quick actions
                Section {
                    Button {
                        // Only enable widgets that can actually render right now.
                        enabledSet = Set(
                            WidgetEngine.realWidgets
                                .filter { WidgetEngine.canRender($0.type, goals: goals, profile: profile) }
                                .map { $0.type.rawValue }
                        )
                        saveWidgets()
                        PulseHaptics.medium()
                    } label: {
                        Label("Enable all".localized, systemImage: "checkmark.square.fill")
                            .foregroundColor(PulseColors.signal)
                    }
                    .listRowBackground(PulseColors.paper)

                    Button {
                        enabledSet = WidgetEngine.defaultEnabledTypes
                        saveWidgets()
                        PulseHaptics.medium()
                    } label: {
                        Label("Reset to defaults".localized, systemImage: "arrow.counterclockwise")
                            .foregroundColor(PulseColors.ink)
                    }
                    .listRowBackground(PulseColors.paper)

                    Button {
                        enabledSet = []
                        saveWidgets()
                        PulseHaptics.medium()
                    } label: {
                        Label("Disable all".localized, systemImage: "square")
                            .foregroundColor(PulseColors.muted)
                    }
                    .listRowBackground(PulseColors.paper)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulseColors.background)
            .navigationTitle("Edit Widgets".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done".localized) { dismiss() }
                        .foregroundColor(PulseColors.ink)
                }
            }
        }
        .onAppear { loadWidgets() }
    }

    private func sizeLabel(_ size: WidgetConfig.WidgetSize) -> String {
        switch size {
        case .small:  return "SMALL"
        case .medium: return "MEDIUM"
        case .large:  return "LARGE"
        }
    }

    private func loadWidgets() {
        let initialized = UserDefaults.standard.bool(forKey: "pulse_widgets_initialized")
        if initialized,
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: enabledWidgetsData) {
            enabledSet = decoded
        } else {
            enabledSet = WidgetEngine.defaultEnabledTypes
            saveWidgets()
        }
    }

    private func saveWidgets() {
        if let encoded = try? JSONEncoder().encode(enabledSet) {
            enabledWidgetsData = encoded
            // Mark initialized so a future empty set is respected
            UserDefaults.standard.set(true, forKey: "pulse_widgets_initialized")
        }
    }
}
