import SwiftUI
import CoreData

enum WidgetType: String, CaseIterable {
    // Progress widgets
    case goalProgress
    case dailyTaskProgress
    case milestoneTracker
    case streakCounter
    case xpProgress
    case levelGauge

    // Time widgets
    case deadlineCountdown
    case timeInvested
    case dailyTimeGoal
    case weeklyActivity

    // Stats widgets
    case goalsCompleted
    case tasksCompleted
    case focusMinutes
    case consistencyScore

    // Motivation widgets
    case motivationQuote
    case probabilityScore
    case momentumTrend
    case categoryBreakdown

    // Category-specific
    case fitnessTracker
    case financeTracker
    case learningTracker
    case healthTracker
    case creativeTracker
    case careerTracker

    // Social widgets
    case streakCompare

    // Micro widgets
    case nextTask
    case urgencyAlert
    case achievementProgress
    case weeklyGoal
}

struct WidgetConfig: Identifiable {
    let id = UUID()
    let type: WidgetType
    let size: WidgetSize

    enum WidgetSize {
        case small, medium, large
    }
}

struct DynamicWidgetGrid: View {
    let goals: [Goal]
    let profile: UserProfile?

    // Observing the same key the editor writes to so this grid rebuilds the
    // moment the user toggles a widget on/off.
    @AppStorage("pulse_enabled_widgets") private var enabledWidgetsData: Data = Data()

    private var widgets: [WidgetConfig] {
        _ = enabledWidgetsData  // touch the dependency so SwiftUI re-renders
        return WidgetEngine.generateWidgets(for: goals, profile: profile)
    }

    /// Lay the enabled widgets out into rows: two consecutive `.small` widgets
    /// share a row; `.medium`/`.large` each take a full row. Order is preserved
    /// and EVERY enabled widget is included. This replaces the old index-parity
    /// pairing, which silently dropped any widget sitting at an odd index right
    /// after a lone small (e.g. the Daily Quote once all widgets were enabled).
    private var widgetRows: [[WidgetConfig]] {
        let all = widgets
        var rows: [[WidgetConfig]] = []
        var i = 0
        while i < all.count {
            let w = all[i]
            if w.size == .small, i + 1 < all.count, all[i + 1].size == .small {
                rows.append([w, all[i + 1]])
                i += 2
            } else {
                rows.append([w])
                i += 1
            }
        }
        return rows
    }

    @Environment(AppState.self) private var appState

    /// Each widget gets a CONTEXTUAL tap action — or none. Goal/task widgets jump
    /// to Goals so you can act on your plan; the Focus widget starts a session;
    /// stat widgets open Progress; the daily quote isn't tappable (it has its own
    /// Save button). So widgets do DIFFERENT things, and not all are interactive.
    private func action(for type: WidgetType) -> (() -> Void)? {
        switch type {
        case .motivationQuote:
            return nil   // non-interactive — has its own Save button
        case .dailyTaskProgress, .nextTask, .deadlineCountdown, .urgencyAlert:
            return { appState.selectedTab = 1 }            // Goals — act on your plan
        case .focusMinutes:
            return { appState.showingFocusMode = true }    // start a focus session
        default:
            return { appState.showingProgress = true }     // stats → Progress
        }
    }

    @ViewBuilder
    private func cell(_ widget: WidgetConfig) -> some View {
        if let act = action(for: widget.type) {
            Button { act() } label: {
                WidgetRenderer(config: widget, goals: goals, profile: profile)
            }
            .buttonStyle(.plain)
        } else {
            WidgetRenderer(config: widget, goals: goals, profile: profile)
        }
    }

    var body: some View {
        Group {
            if widgets.isEmpty {
                // User disabled everything — tell them how to bring widgets back
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 28))
                        .foregroundColor(PulseColors.muted)
                    Text("No widgets enabled".localized)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PulseColors.ink)
                    Text("Tap Edit above to turn widgets on.".localized)
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
                .background(PulseColors.paper)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, PulseSpacing.screenEdge)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(widgetRows.enumerated()), id: \.offset) { _, row in
                        if row.count == 2 {
                            HStack(spacing: 10) {
                                cell(row[0])
                                cell(row[1])
                            }
                        } else {
                            cell(row[0])
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

struct WidgetEngine {
    /// All widgets that have a real, data-backed render. The editor only shows
    /// these so the user can never enable a widget that doesn't render. The
    /// order here is the order they appear on the dashboard.
    // A deliberately SMALL, distinct set — no overlapping/duplicate widgets, so
    // the dashboard stays clean. (Trimmed from 14: dropped Momentum/Consistency/
    // Urgency which duplicated Streak & Deadline, plus AI-Probability, Goals/
    // Pulses-Completed, Next-Pulse, and Weekly-Activity which were niche or
    // overlapped Today's Tasks.)
    static let realWidgets: [(type: WidgetType, size: WidgetConfig.WidgetSize, name: String, icon: String)] = [
        (.dailyTaskProgress, .medium, "Today's Tasks",       "checklist"),
        (.streakCounter,     .small,  "Streak Counter",      "flame.fill"),
        (.xpProgress,        .small,  "XP Progress",         "star.fill"),
        (.deadlineCountdown, .small,  "Deadline Countdown",  "clock.fill"),
        (.focusMinutes,      .small,  "Focus Time",          "timer"),
        (.motivationQuote,   .large,  "Daily Quote",         "quote.opening")
    ]

    /// Default set of widgets enabled on first install. Keeps the dashboard
    /// scannable without overwhelming a new user.
    static let defaultEnabledTypes: Set<String> = [
        WidgetType.dailyTaskProgress.rawValue,
        WidgetType.deadlineCountdown.rawValue,
        WidgetType.focusMinutes.rawValue,
        WidgetType.motivationQuote.rawValue
    ]

    /// Read the user's enabled set from UserDefaults. Defaults to the curated
    /// starter set ONLY if the user has never opened the editor. After the user
    /// has chosen, an empty set is a valid choice — we respect it.
    static func enabledTypes() -> Set<String> {
        let initialized = UserDefaults.standard.bool(forKey: "pulse_widgets_initialized")
        if initialized,
           let data = UserDefaults.standard.data(forKey: "pulse_enabled_widgets"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return decoded
        }
        return defaultEnabledTypes
    }

    /// Generate the dashboard widget configs honoring the user's toggle choices.
    /// When no goals exist, render only the motivation quote (if enabled).
    static func generateWidgets(for goals: [Goal], profile: UserProfile?) -> [WidgetConfig] {
        let enabled = enabledTypes()

        // Every enabled widget renders at all times — with or without a goal or
        // any tasks today. Goal/task widgets fall back to a graceful empty state
        // ("Nothing to do today", "All done", …) rather than disappearing, so the
        // home screen shows exactly what the user toggled on. (canRender is always
        // true now; the filter is kept for clarity / future use.)
        return realWidgets
            .filter { enabled.contains($0.type.rawValue) }
            .filter { canRender($0.type, goals: goals, profile: profile) }
            .map { WidgetConfig(type: $0.type, size: $0.size) }
    }

    /// Whether a widget has the data it needs to render something real right now.
    /// Today every widget except the Daily Quote requires at least one goal
    /// (see the goals.isEmpty guard above), so the rule is goal-presence.
    static func canRender(_ type: WidgetType, goals: [Goal], profile: UserProfile?) -> Bool {
        // Every widget can be added and shown at ALL times — whether or not the
        // user has an active goal or any tasks today. Widgets that draw on
        // goal/task data render a graceful empty state ("Nothing to do today",
        // "All done", "no deadline set", …) instead of being hidden, so the user
        // can always enable any widget they want from the editor.
        return true
    }

    /// Human-readable reason a widget can't be enabled yet, or nil if it can.
    static func unavailableReason(_ type: WidgetType, goals: [Goal], profile: UserProfile?) -> String? {
        guard !canRender(type, goals: goals, profile: profile) else { return nil }
        return "Add a goal first to use this widget".localized
    }
}

struct WidgetRenderer: View {
    let config: WidgetConfig
    let goals: [Goal]
    let profile: UserProfile?
    @ObservedObject private var social = SocialStore.shared

    private var primaryGoal: Goal? { goals.first }

    var body: some View {
        Group {
            switch config.type {
            case .goalProgress: goalProgressWidget
            case .dailyTaskProgress: dailyTaskWidget
            case .milestoneTracker: milestoneWidget
            case .streakCounter: streakWidget
            case .xpProgress: xpWidget
            case .levelGauge: levelWidget
            case .deadlineCountdown: deadlineWidget
            case .timeInvested: timeInvestedWidget
            case .dailyTimeGoal: dailyTimeWidget
            case .weeklyActivity: weeklyActivityWidget
            case .goalsCompleted: goalsCompletedWidget
            case .tasksCompleted: tasksCompletedWidget
            case .focusMinutes: focusWidget
            case .consistencyScore: consistencyWidget
            case .motivationQuote: motivationWidget
            case .probabilityScore: probabilityWidget
            case .momentumTrend: momentumWidget
            case .categoryBreakdown: categoryWidget
            case .fitnessTracker: fitnessWidget
            case .financeTracker: financeWidget
            case .learningTracker: learningWidget
            case .healthTracker: healthWidget
            case .creativeTracker: creativeWidget
            case .careerTracker: careerWidget
            case .streakCompare: streakCompareWidget
            case .nextTask: nextTaskWidget
            case .urgencyAlert: urgencyWidget
            case .achievementProgress: achievementWidget
            case .weeklyGoal: weeklyGoalWidget
            }
        }
    }

    // MARK: - Shared rich building blocks (mirror the Active Goal card)

    /// Detailed stat widget: icon chip + eyebrow label, big value, optional
    /// progress bar, optional context line. Used by every small widget so they
    /// all carry the same density as the Active Goal hero card.
    private func statWidget(icon: String, tint: Color, label: String, value: String,
                            detail: String? = nil, progress: Double? = nil,
                            valueColor: Color = PulseColors.textPrimary) -> some View {
        WidgetCard(size: .small, accentColor: tint) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.14))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(tint)
                    }
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(PulseColors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PulseColors.surfaceContainer).frame(height: 4)
                            Capsule().fill(tint)
                                .frame(width: geo.size.width * min(max(progress, 0), 1), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PulseColors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Eyebrow header (icon chip + label + optional trailing value) for
    /// medium / large widgets.
    private func widgetHeader(icon: String, tint: Color, _ label: String,
                              trailing: String? = nil, trailingColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(PulseColors.textTertiary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(trailingColor ?? PulseColors.textPrimary)
            }
        }
    }

    /// A thin progress bar matching the stat-widget style.
    private func barTrack(_ progress: Double, tint: Color, height: CGFloat = 6) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(PulseColors.surfaceContainer).frame(height: height)
                Capsule().fill(tint)
                    .frame(width: geo.size.width * min(max(progress, 0), 1), height: height)
            }
        }
        .frame(height: height)
    }

    private func nextStreakMilestone(_ streak: Int) -> Int {
        [7, 14, 30, 60, 100, 180, 365].first { $0 > streak } ?? (streak + 30)
    }

    private func shortWidgetDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: - Widget Views

    private var goalProgressWidget: some View {
        let goal = primaryGoal
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: goal?.categoryEnum.iconName ?? "target")
                        .foregroundColor(goal?.categoryEnum.color ?? PulseColors.primary)
                    Text(goal?.titleValue ?? "No Goal")
                        .font(PulseTypography.labelLargeEmphasized)
                        .foregroundColor(PulseColors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int((goal?.progressPercentage ?? 0) * 100))%")
                        .font(PulseTypography.titleMedium)
                        .foregroundColor(PulseColors.primary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(PulseColors.surfaceContainer)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(colors: [goal?.categoryEnum.color ?? PulseColors.primary, PulseColors.primary], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: geo.size.width * (goal?.progressPercentage ?? 0))
                    }
                }
                .frame(height: 10)
                if let goal {
                    HStack {
                        Text("\(goal.completedTodaysTasks)/\(goal.todaysTasks.count) tasks today")
                            .font(PulseTypography.labelSmall)
                            .foregroundColor(PulseColors.textTertiary)
                        Spacer()
                        Text("\(goal.daysRemaining)d left")
                            .font(PulseTypography.labelSmall)
                            .foregroundColor(goal.daysRemaining < 7 ? PulseColors.danger : PulseColors.textTertiary)
                    }
                }
            }
        }
    }

    private var dailyTaskWidget: some View {
        let tasks = primaryGoal?.todaysTasks ?? []
        let done = tasks.filter { $0.isCompleted }.count
        let pct = tasks.isEmpty ? 0.0 : Double(done) / Double(tasks.count)
        let allDone = !tasks.isEmpty && done == tasks.count
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 10) {
                widgetHeader(icon: "checklist", tint: PulseColors.success, "Today's Tasks",
                             trailing: "\(done)/\(tasks.count)",
                             trailingColor: allDone ? PulseColors.success : PulseColors.textPrimary)
                barTrack(pct, tint: PulseColors.success)
                if tasks.isEmpty {
                    Text("Nothing to do today")
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.textTertiary)
                } else {
                    VStack(spacing: 7) {
                        ForEach(tasks.prefix(3), id: \.objectID) { t in
                            HStack(spacing: 8) {
                                Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(t.isCompleted ? PulseColors.success : PulseColors.textTertiary)
                                Text(t.title ?? "Pulse")
                                    .font(.system(size: 12.5))
                                    .strikethrough(t.isCompleted, color: PulseColors.textTertiary)
                                    .foregroundColor(t.isCompleted ? PulseColors.textTertiary : PulseColors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if tasks.count > 3 {
                            Text("+\(tasks.count - 3) more")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(PulseColors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var milestoneWidget: some View {
        let milestones = primaryGoal?.milestonesArray ?? []
        let completed = milestones.filter { $0.isCompleted }.count
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundColor(PulseColors.secondary)
                    Text("Milestones".localized)
                        .font(PulseTypography.labelLargeEmphasized)
                        .foregroundColor(PulseColors.textPrimary)
                }
                HStack(spacing: 4) {
                    ForEach(0..<min(milestones.count, 8), id: \.self) { i in
                        Circle()
                            .fill(i < completed ? PulseColors.secondary : PulseColors.surfaceContainer)
                            .frame(width: 10, height: 10)
                    }
                }
                Text("\(completed)/\(milestones.count)")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
            }
        }
    }

    private var streakWidget: some View {
        let streak = Int(profile?.currentStreak ?? 0)
        let best = Int(profile?.longestStreak ?? 0)
        let next = nextStreakMilestone(streak)
        return statWidget(
            icon: "flame.fill", tint: PulseColors.warning,
            label: "Current Streak", value: "\(streak)d",
            detail: best > 0 ? "Best \(best)d · \(max(0, next - streak))d to \(next)"
                             : "\(max(0, next - streak))d to \(next)-day",
            progress: next > 0 ? Double(streak) / Double(next) : nil
        )
    }

    private var xpWidget: some View {
        let xp = Int(profile?.totalXP ?? 0)
        let level = Int(profile?.currentLevel ?? 1)
        let toNext = max(0, Int(profile?.xpForNextLevel ?? 200) - xp)
        return statWidget(
            icon: "star.fill", tint: PulseColors.warning,
            label: "Total XP", value: "\(xp)",
            detail: "Lv \(level) · \(toNext) XP to Lv \(level + 1)",
            progress: profile?.xpProgress
        )
    }

    private var levelWidget: some View {
        WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(PulseColors.tertiary)
                    Text("Level \(profile?.currentLevel ?? 1)")
                        .font(PulseTypography.titleMedium)
                        .foregroundColor(PulseColors.textPrimary)
                    Spacer()
                    Text("\(Int((profile?.xpProgress ?? 0) * 100))%")
                        .font(PulseTypography.labelMedium)
                        .foregroundColor(PulseColors.tertiary)
                }
                ProgressView(value: profile?.xpProgress ?? 0)
                    .tint(PulseColors.tertiary)
                Text("\(profile?.totalXP ?? 0)/\(profile?.xpForNextLevel ?? 200) XP to next level")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
            }
        }
    }

    private var deadlineWidget: some View {
        let goal = primaryGoal
        let days = goal?.daysRemaining ?? 0
        let tint = days < 7 ? PulseColors.danger : (days < 30 ? PulseColors.warning : PulseColors.primary)
        var elapsed: Double? = nil
        if let start = goal?.createdAt, let end = goal?.deadline {
            let total = end.timeIntervalSince(start)
            if total > 0 { elapsed = Date().timeIntervalSince(start) / total }
        }
        return statWidget(
            icon: "clock.fill", tint: tint,
            label: "Deadline", value: "\(days)d",
            detail: goal?.deadline.map { "by " + shortWidgetDate($0) } ?? "no deadline set",
            progress: elapsed, valueColor: tint
        )
    }

    private var timeInvestedWidget: some View {
        let mins = primaryGoal?.totalFocusMinutes ?? 0
        return WidgetCard(size: .small) {
            VStack(spacing: 6) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(PulseColors.primary)
                Text(mins >= 60 ? "\(mins / 60)h" : "\(mins)m")
                    .font(PulseTypography.headlineMedium)
                    .foregroundColor(PulseColors.textPrimary)
                Text("Invested")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var dailyTimeWidget: some View {
        WidgetCard(size: .small) {
            VStack(spacing: 6) {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 22))
                    .foregroundColor(PulseColors.success)
                Text("\(String(format: "%.1f", primaryGoal?.availableTimePerDay ?? 0))h")
                    .font(PulseTypography.headlineMedium)
                    .foregroundColor(PulseColors.textPrimary)
                Text("Daily Goal")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var weeklyActivityWidget: some View {
        let tasksPerDay = computeWeeklyActivity()
        let maxTasks = max(tasksPerDay.max() ?? 1, 1)
        let weekTotal = tasksPerDay.reduce(0, +)
        let bestDay = tasksPerDay.firstIndex(of: tasksPerDay.max() ?? 0)
        return WidgetCard(size: .large) {
            VStack(alignment: .leading, spacing: 12) {
                widgetHeader(icon: "calendar", tint: PulseColors.primary, "This Week",
                             trailing: "\(weekTotal) done", trailingColor: PulseColors.textPrimary)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        let isToday = day == Calendar.current.component(.weekday, from: Date()) - 1
                        let count = tasksPerDay[day]
                        VStack(spacing: 5) {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(count > 0 ? PulseColors.primary : PulseColors.textTertiary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(count > 0
                                      ? PulseColors.primary.opacity(0.35 + 0.65 * Double(count) / Double(maxTasks))
                                      : PulseColors.surfaceContainer)
                                .frame(height: 42)
                            Text(["S","M","T","W","T","F","S"][day])
                                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                                .foregroundColor(isToday ? PulseColors.primary : PulseColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(weekTotal == 0 ? "No pulses completed yet this week."
                     : "Best day: \(["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][bestDay ?? 0]) · \(weekTotal) pulses total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PulseColors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func computeWeeklyActivity() -> [Int] {
        var counts = [Int](repeating: 0, count: 7)
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return counts }
        let allTasks = goals.flatMap { $0.dailyTasksArray }
        for task in allTasks where task.isCompleted {
            guard let completed = task.completedDate else { continue }
            let dayIndex = calendar.component(.weekday, from: completed) - 1
            if completed >= weekStart && completed <= today {
                counts[dayIndex] += 1
            }
        }
        return counts
    }

    private var goalsCompletedWidget: some View {
        let all = profile?.goalsArray ?? []
        let count = all.filter { $0.statusEnum == .completed }.count
        let total = all.count
        return statWidget(
            icon: "checkmark.seal.fill", tint: PulseColors.success,
            label: "Goals Done", value: "\(count)",
            detail: total > 0 ? "of \(total) total" : "no goals yet",
            progress: total > 0 ? Double(count) / Double(total) : nil
        )
    }

    private var tasksCompletedWidget: some View {
        let all = goals.flatMap { $0.dailyTasksArray }
        let count = all.filter { $0.isCompleted }.count
        let total = all.count
        let pct = total > 0 ? Int(Double(count) / Double(total) * 100) : 0
        return statWidget(
            icon: "checkmark.circle.fill", tint: PulseColors.success,
            label: "Pulses Done", value: "\(count)",
            detail: total > 0 ? "\(pct)% of \(total) pulses" : "no pulses yet",
            progress: total > 0 ? Double(count) / Double(total) : nil
        )
    }

    private var focusWidget: some View {
        let total = goals.reduce(0) { $0 + $1.totalFocusMinutes }
        let value = total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
        return statWidget(
            icon: "timer", tint: PulseColors.primary,
            label: "Focus Time", value: total > 0 ? value : "0m",
            detail: total > 0 ? "across \(goals.count) goal\(goals.count == 1 ? "" : "s")"
                              : "start a focus session",
            progress: nil
        )
    }

    private var consistencyWidget: some View {
        let streak = Int(profile?.currentStreak ?? 0)
        let score = min(100, streak * 10)
        let tint = score >= 70 ? PulseColors.success : score >= 40 ? PulseColors.warning : PulseColors.danger
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 10) {
                widgetHeader(icon: "chart.line.uptrend.xyaxis", tint: PulseColors.success, "Consistency",
                             trailing: "\(score)%", trailingColor: tint)
                barTrack(Double(score) / 100.0, tint: tint)
                Text(score >= 70 ? "On fire — your \(streak)-day streak is going strong."
                   : score >= 40 ? "Solid — keep your \(streak)-day streak alive."
                   : "Build it up — complete a pulse today to start a streak.")
                    .font(.system(size: 12))
                    .foregroundColor(PulseColors.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var motivationWidget: some View {
        let quote = DailyQuotes.current()
        let saved = social.isQuoteSaved(quote)
        return WidgetCard(size: .large) {
            VStack(alignment: .leading, spacing: 10) {
                widgetHeader(icon: "quote.opening", tint: PulseColors.primary, "Daily Motivation")
                Text(quote)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PulseColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 10))
                    Text(saved ? "Saved to your collection" : "Long-press to save")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(saved ? PulseColors.primary : PulseColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button { social.toggleSaveQuote(quote); PulseHaptics.light() } label: {
                    Label(saved ? "Unsave quote" : "Save quote",
                          systemImage: saved ? "bookmark.slash" : "bookmark")
                }
            }
        }
    }

    private var probabilityWidget: some View {
        let prob = Int(primaryGoal?.aiProbabilityScore ?? 0)
        let tint = prob >= 70 ? PulseColors.success : prob >= 40 ? PulseColors.warning : PulseColors.danger
        let label = prob >= 70 ? "Likely to hit it" : prob >= 40 ? "Possible — push" : "Stretch goal"
        return statWidget(
            icon: "brain.head.profile", tint: PulseColors.tertiary,
            label: "AI Probability", value: prob > 0 ? "\(prob)%" : "—",
            detail: prob > 0 ? label : "Not analyzed yet",
            progress: prob > 0 ? Double(prob) / 100.0 : nil,
            valueColor: prob > 0 ? tint : PulseColors.textPrimary
        )
    }

    private var momentumWidget: some View {
        let streak = Int(profile?.currentStreak ?? 0)
        let state = streak >= 3 ? "Rising" : streak >= 1 ? "Steady" : "Build up"
        let tint = streak >= 3 ? PulseColors.success : streak >= 1 ? PulseColors.warning : PulseColors.textTertiary
        let arrow = streak >= 3 ? "arrow.up.right" : streak >= 1 ? "arrow.right" : "arrow.down.right"
        return statWidget(
            icon: arrow, tint: tint,
            label: "Momentum", value: state,
            detail: "\(streak)-day streak",
            progress: min(1.0, Double(streak) / 7.0), valueColor: tint
        )
    }

    private var categoryWidget: some View {
        let categories = Dictionary(grouping: goals, by: { $0.categoryEnum })
        return WidgetCard(size: .large) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Goal Categories")
                    .font(PulseTypography.labelLargeEmphasized)
                    .foregroundColor(PulseColors.textPrimary)
                if categories.isEmpty {
                    Text("Create goals to see breakdown")
                        .font(PulseTypography.bodySmall)
                        .foregroundColor(PulseColors.textTertiary)
                } else {
                    ForEach(Array(categories.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { cat in
                        HStack(spacing: 8) {
                            Image(systemName: cat.iconName)
                                .font(.system(size: 14))
                                .foregroundColor(cat.color)
                                .frame(width: 20)
                            Text(cat.displayName)
                                .font(PulseTypography.labelMedium)
                                .foregroundColor(PulseColors.textPrimary)
                            Spacer()
                            Text("\(categories[cat]?.count ?? 0)")
                                .font(PulseTypography.labelMedium)
                                .foregroundColor(PulseColors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func categorySpecificWidget(icon: String, title: String, color: Color, detail: String) -> some View {
        WidgetCard(size: .large) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Text(title)
                        .font(PulseTypography.labelLargeEmphasized)
                        .foregroundColor(PulseColors.textPrimary)
                }
                Text(detail)
                    .font(PulseTypography.bodySmall)
                    .foregroundColor(PulseColors.textSecondary)
                if let goal = primaryGoal {
                    ProgressView(value: goal.progressPercentage)
                        .tint(color)
                }
            }
        }
    }

    private var fitnessWidget: some View {
        categorySpecificWidget(icon: "figure.run", title: "Fitness Goal", color: GoalCategory.fitness.color,
                               detail: "Keep pushing! Track workouts and body metrics.")
    }
    private var financeWidget: some View {
        categorySpecificWidget(icon: "dollarsign.circle.fill", title: "Finance Goal", color: GoalCategory.finance.color,
                               detail: "Track revenue, savings, and spending milestones.")
    }
    private var learningWidget: some View {
        categorySpecificWidget(icon: "book.fill", title: "Learning Goal", color: GoalCategory.learning.color,
                               detail: "Complete lessons and track quiz scores.")
    }
    private var healthWidget: some View {
        categorySpecificWidget(icon: "heart.fill", title: "Health Goal", color: GoalCategory.health.color,
                               detail: "Build healthy habits one day at a time.")
    }
    private var creativeWidget: some View {
        categorySpecificWidget(icon: "paintbrush.fill", title: "Creative Goal", color: GoalCategory.creative.color,
                               detail: "Create, share, and iterate on your craft.")
    }
    private var careerWidget: some View {
        categorySpecificWidget(icon: "briefcase.fill", title: "Career Goal", color: GoalCategory.career.color,
                               detail: "Level up skills and hit career milestones.")
    }

    private var streakCompareWidget: some View {
        WidgetCard(size: .small) {
            VStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 22))
                    .foregroundColor(PulseColors.warning)
                Text("\(profile?.longestStreak ?? 0)")
                    .font(PulseTypography.headlineMedium)
                    .foregroundColor(PulseColors.textPrimary)
                Text("Best Streak")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var nextTaskWidget: some View {
        let task = primaryGoal?.todaysTasks.first(where: { !$0.isCompleted })
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 10) {
                widgetHeader(icon: "arrow.right.circle.fill", tint: PulseColors.primary, "Next Pulse",
                             trailing: task.map { "~\($0.estimatedMinutes)m" },
                             trailingColor: PulseColors.textTertiary)
                if let task {
                    Text(task.title ?? "Pulse")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PulseColors.textPrimary)
                        .lineLimit(2)
                    if let goal = primaryGoal {
                        HStack(spacing: 6) {
                            Image(systemName: goal.categoryEnum.iconName)
                                .font(.system(size: 11))
                                .foregroundColor(goal.categoryEnum.color)
                            Text(goal.titleValue)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.textTertiary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(PulseColors.success)
                        Text(primaryGoal == nil ? "Nothing to do today" : "All done for today!")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PulseColors.textPrimary)
                    }
                }
            }
        }
    }

    private var urgencyWidget: some View {
        let goal = primaryGoal
        let urgency = goal?.urgencyLevelEnum ?? .low
        let days = goal?.daysRemaining ?? 0
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 10) {
                widgetHeader(icon: urgency == .critical ? "exclamationmark.triangle.fill" : "gauge.high",
                             tint: urgency.color, "Urgency",
                             trailing: urgency.displayName, trailingColor: urgency.color)
                Text(goal?.titleValue ?? "No active goal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PulseColors.textPrimary)
                    .lineLimit(1)
                Text(days <= 0 ? "Deadline reached"
                               : "\(days) days left · \(goal?.completedSteps ?? 0)/\(goal?.totalSteps ?? 0) pulses")
                    .font(.system(size: 12))
                    .foregroundColor(PulseColors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var achievementWidget: some View {
        let count = profile?.achievementsArray.count ?? 0
        return WidgetCard(size: config.size) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Achievements")
                        .font(PulseTypography.labelLargeEmphasized)
                        .foregroundColor(PulseColors.textPrimary)
                    Text("\(count) unlocked")
                        .font(PulseTypography.bodySmall)
                        .foregroundColor(PulseColors.textTertiary)
                }
                Spacer()
                Image(systemName: "medal.fill")
                    .font(.system(size: 28))
                    .foregroundColor(count > 0 ? PulseColors.warning : PulseColors.textTertiary)
            }
        }
    }

    private var weeklyGoalWidget: some View {
        let todayTasks = goals.flatMap { $0.todaysTasks }
        let done = todayTasks.filter { $0.isCompleted }.count
        return WidgetCard(size: config.size) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(PulseColors.primary)
                    Text("Daily Goal")
                        .font(PulseTypography.labelLargeEmphasized)
                        .foregroundColor(PulseColors.textPrimary)
                    Spacer()
                    Text("\(done)/\(max(todayTasks.count, 1))")
                        .font(PulseTypography.labelMedium)
                        .foregroundColor(PulseColors.textTertiary)
                }
                ProgressView(value: todayTasks.isEmpty ? 0 : Double(done) / Double(todayTasks.count))
                    .tint(PulseColors.primary)
            }
        }
    }
}

struct WidgetCard<Content: View>: View {
    let size: WidgetConfig.WidgetSize
    var accentColor: Color = PulseColors.primary
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(size == .small ? PulseSpacing.md : PulseSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
            )
    }
}
