import SwiftUI
import UIKit
import CoreData

/// Real Apple calendar (UICalendarView, iOS 16+) for a Transformation goal.
/// Decorates every training day so the user sees done / today / upcoming /
/// missed at a glance. Tapping a date opens a quick summary of that day's
/// workout.
struct WorkoutCalendar: View {
    // @ObservedObject (was `let`) so SwiftUI subscribes to the goal and re-runs
    // the body when its dailyTasks change — without this the calendar never
    // re-decorated a day that was completed while the screen stayed visible.
    @ObservedObject var goal: Goal
    /// Compact mode swaps the full 380pt UICalendarView for a tidy horizontal
    /// strip of training-day chips — far less empty space on the lean
    /// Custom Workout detail screen. Defaults false so the Transformation caller
    /// keeps the full calendar unchanged.
    var compact: Bool = false
    @State private var selected: DateComponents?
    @State private var showingDayDetail: DailyTask?

    private var tasks: [DailyTask] {
        (goal.dailyTasks as? Set<DailyTask> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var totalDone: Int { tasks.filter { $0.isCompleted }.count }
    private var totalDays: Int { tasks.count }

    private var startDate: Date {
        goal.createdAt ?? tasks.first?.scheduledDate ?? Date()
    }
    private var endDate: Date {
        goal.deadline
            ?? tasks.last?.scheduledDate
            ?? Calendar.current.date(byAdding: .month, value: 3, to: startDate)
            ?? startDate
    }

    var body: some View {
        Group {
            if compact {
                compactStrip
            } else {
                fullCalendar
            }
        }
        .sheet(item: $showingDayDetail) { task in
            DayDetailSheet(task: task)
        }
    }

    // MARK: Header (shared)

    private var header: some View {
        HStack {
            Text("WORKOUT CALENDAR")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.muted)
            Spacer()
            Text("\(totalDone) / \(totalDays) done")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(PulseColors.signal)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Compact — horizontal training-day chips

    private var compactStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if tasks.isEmpty {
                Text("No training days scheduled yet.")
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 14)
                    .background(PulseColors.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tasks) { task in
                            dayChip(task)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private enum DayStatus { case done, today, missed, upcoming }

    private func status(for task: DailyTask) -> DayStatus {
        if task.isCompleted { return .done }
        let cal = Calendar.current
        if let d = task.scheduledDate {
            if cal.isDateInToday(d) { return .today }
            if cal.startOfDay(for: d) < cal.startOfDay(for: Date()) { return .missed }
        }
        return .upcoming
    }

    @ViewBuilder
    private func dayChip(_ task: DailyTask) -> some View {
        let st = status(for: task)
        let cal = Calendar.current
        let date = task.scheduledDate
        let weekday = date.map { cal.shortWeekdaySymbols[cal.component(.weekday, from: $0) - 1].uppercased() } ?? ""
        let dayNum = date.map { "\(cal.component(.day, from: $0))" } ?? "—"

        Button { showingDayDetail = task } label: {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(st == .done ? PulseColors.onPrimary.opacity(0.85) : PulseColors.muted)
                ZStack {
                    if st == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(PulseColors.onPrimary)
                    } else {
                        Text(dayNum)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(st == .missed ? PulseColors.muted : PulseColors.ink)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .frame(width: 52, height: 60)
            .background(chipBackground(st))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(st == .today ? PulseColors.signal : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chipBackground(_ st: DayStatus) -> Color {
        switch st {
        case .done:     return PulseColors.signal
        case .today:    return PulseColors.signal.opacity(0.10)
        case .missed:   return PulseColors.muted.opacity(0.12)
        case .upcoming: return PulseColors.surfaceContainer
        }
    }

    // MARK: Full calendar (Transformation)

    private var fullCalendar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header — lives OUTSIDE the calendar card so it can't
            // collide with UICalendarView's native "May 2026" month header.
            header

            // The actual calendar card. UICalendarView paints its own month
            // header at the top of its frame, so nothing competes with it.
            VStack(spacing: 12) {
                CalendarRepresentable(
                    tasks: tasks,
                    // Threading the done-count through as a stored property means a
                    // re-run of body with a new count differs the representable, so
                    // SwiftUI calls updateUIView → reloadDecorations (in place, no
                    // teardown), repainting the just-completed day immediately.
                    completedCount: totalDone,
                    startDate: startDate,
                    endDate: endDate,
                    selected: $selected,
                    onSelectTask: { showingDayDetail = $0 }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 380)

                HStack(spacing: 12) {
                    legendDot(color: PulseColors.signal, label: "Done")
                    legendDot(color: .clear, ring: PulseColors.signal, label: "Today")
                    legendDot(color: PulseColors.muted.opacity(0.25), label: "Missed")
                }
                .padding(.bottom, 4)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func legendDot(color: Color, ring: Color? = nil, label: String) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(color).frame(width: 10, height: 10)
                if let ring {
                    Circle().stroke(ring, lineWidth: 1.5).frame(width: 10, height: 10)
                }
            }
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(PulseColors.muted)
        }
    }
}

// MARK: - UICalendarView bridge

private struct CalendarRepresentable: UIViewRepresentable {
    let tasks: [DailyTask]
    /// Number of completed training days. Stored only so SwiftUI re-runs
    /// updateUIView when a day flips done/undone (the [DailyTask] array can be
    /// the same object identities, which alone won't trigger an update).
    let completedCount: Int
    let startDate: Date
    let endDate: Date
    @Binding var selected: DateComponents?
    let onSelectTask: (DailyTask) -> Void

    func makeUIView(context: Context) -> UICalendarView {
        let cal = UICalendarView()
        cal.calendar = Calendar(identifier: .gregorian)
        cal.locale = Locale.current
        // Let SwiftUI dictate width — without these the UICalendarView demands
        // its intrinsic minimum width and overflows the card.
        cal.translatesAutoresizingMaskIntoConstraints = false
        cal.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cal.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Visible date range = start of plan to deadline
        let calCalendar = cal.calendar
        let startComp = calCalendar.dateComponents([.year, .month, .day], from: startDate)
        let endComp = calCalendar.dateComponents([.year, .month, .day], from: endDate)
        cal.availableDateRange = DateInterval(
            start: calCalendar.date(from: startComp) ?? startDate,
            end: calCalendar.date(from: endComp) ?? endDate
        )

        cal.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        cal.selectionBehavior = selection
        cal.tintColor = UIColor(PulseColors.signal)
        cal.backgroundColor = .clear

        // Open on the month containing today (or the goal's start if future)
        let todayComp = calCalendar.dateComponents([.year, .month], from: Date())
        cal.visibleDateComponents = todayComp
        return cal
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        // Re-decorate visible months when tasks change
        let calCalendar = uiView.calendar
        let allDates = tasks.compactMap { $0.scheduledDate }
            .map { calCalendar.dateComponents([.year, .month, .day], from: $0) }
        uiView.reloadDecorations(forDateComponents: allDates, animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: CalendarRepresentable
        init(parent: CalendarRepresentable) { self.parent = parent }

        private func task(for dateComponents: DateComponents) -> DailyTask? {
            let cal = Calendar.current
            guard let target = cal.date(from: dateComponents) else { return nil }
            let day = cal.startOfDay(for: target)
            return parent.tasks.first { task in
                guard let scheduled = task.scheduledDate else { return false }
                return cal.isDate(scheduled, inSameDayAs: day)
            }
        }

        // Decorations on each day cell
        func calendarView(_ calendarView: UICalendarView,
                          decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let task = task(for: dateComponents) else { return nil }

            if task.isCompleted {
                // Filled red dot — done
                return .image(
                    UIImage(systemName: "checkmark.circle.fill"),
                    color: UIColor(PulseColors.signal),
                    size: .large
                )
            }

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            if let scheduled = task.scheduledDate, cal.startOfDay(for: scheduled) < today {
                // Past + not done — missed
                return .default(color: UIColor(PulseColors.muted.opacity(0.6)),
                                size: .small)
            }
            // Upcoming
            return .default(color: UIColor(PulseColors.signal.opacity(0.5)), size: .small)
        }

        // Tapping a date
        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           didSelectDate dateComponents: DateComponents?) {
            parent.selected = dateComponents
            if let comp = dateComponents, let task = task(for: comp) {
                parent.onSelectTask(task)
            }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           canSelectDate dateComponents: DateComponents?) -> Bool {
            true
        }
    }
}

// MARK: - Day Detail Sheet

private struct DayDetailSheet: View {
    @ObservedObject var task: DailyTask
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var viewContext

    private var dateLabel: String {
        guard let d = task.scheduledDate else { return "" }
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: d)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(dateLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(PulseColors.muted)
                    Text(task.titleValue)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(PulseColors.ink)

                    HStack(spacing: 8) {
                        statusPill
                        if task.estimatedMinutes > 0 {
                            Label("\(task.estimatedMinutes) min", systemImage: "clock")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PulseColors.muted)
                        }
                    }

                    if !task.howTo.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("WORKOUT")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.4)
                                .foregroundColor(PulseColors.muted)
                            Text(task.howTo)
                                .font(.system(size: 14))
                                .foregroundColor(PulseColors.ink)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PulseColors.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !task.isCompleted, let scheduled = task.scheduledDate,
                       Calendar.current.isDateInToday(scheduled) {
                        Button {
                            // Route through the SAME canonical completion path as the
                            // Today Workout sheet's setDayCompleted — XP / level / streak
                            // / completedDate / currentProgress / markCompletedIfAllStepsDone
                            // all update exactly ONCE, and the guard makes re-tapping a
                            // no-op (no double-credit). It already awards XP via
                            // registerCompletion, so we raise the celebration overlay
                            // directly here rather than calling celebratePulseCompletion
                            // (which would award the XP a second time).
                            let didComplete = task.setCompletion(true, in: viewContext)
                            if didComplete {
                                let profile = UserProfile.fetchOrCreate(in: viewContext)
                                let goalJustFinished = task.goal?.statusEnum == .completed
                                if goalJustFinished {
                                    appState.celebrationData = nil
                                    let goal = task.goal
                                    let days = max(1, Calendar.current.dateComponents([.day],
                                        from: goal?.createdAt ?? Date(), to: Date()).day ?? 1)
                                    let othersDone = goal?.userProfile?.goalsArray.filter {
                                        $0.statusEnum == .completed && $0.objectID != goal?.objectID
                                    }.count ?? 0
                                    appState.celebrateGoalCompletion(
                                        goalTitle: goal?.titleValue ?? "",
                                        daysTaken: days,
                                        totalPulses: Int(goal?.totalSteps ?? 0),
                                        isFirst: othersDone == 0
                                    )
                                } else {
                                    appState.celebrationData = PulseCelebrationData(
                                        pulseNumber: Int(task.stepNumber),
                                        xpGained: Int(task.xpReward),
                                        totalXP: Int(profile.totalXP),
                                        nextPulseTitle: nil,
                                        didLevelUp: false,
                                        newLevel: profile.levelValue,
                                        goalTitle: task.goal?.titleValue,
                                        authorId: AuthManager.shared.currentUser?.userId ?? profile.id?.uuidString ?? "me",
                                        authorName: profile.displayNameValue.isEmpty ? "You" : profile.displayNameValue
                                    )
                                }
                                PulseHaptics.success()
                            }
                            dismiss()
                        } label: {
                            Text("Mark Done")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(PulseColors.signal)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    Spacer(minLength: 30)
                }
                .padding(16)
            }
            .pulseScreen()
            .navigationTitle("Day Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusPill: some View {
        let label: String
        let color: Color
        var textColor: Color = .white
        if task.isCompleted {
            label = "DONE"; color = PulseColors.signal
        } else if let d = task.scheduledDate, Calendar.current.isDateInToday(d) {
            label = "TODAY"; color = PulseColors.signal
        } else if let d = task.scheduledDate, d < Date() {
            // Faded chip + dark text so it reads (white-on-mid-gray was washed out).
            label = "MISSED"; color = PulseColors.muted.opacity(0.18); textColor = PulseColors.textSecondary
        } else {
            label = "UPCOMING"; color = PulseColors.signal.opacity(0.6)
        }
        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Shared completion path

extension DailyTask {
    /// THE single way any surface (the calendar's Day Detail, the Today Workout
    /// sheet, …) marks a training day done or un-done. Routes XP / level / streak
    /// / save / widget through the ONE canonical `UserProfile.registerCompletion`
    /// (never `celebratePulseCompletion`, which would award again), writes
    /// `completedDate` + `verificationStatus`, and funnels through
    /// `markCompletedIfAllStepsDone` so progress + goal status update exactly once.
    ///
    /// Idempotent: guards on the real `isCompleted != complete` transition so
    /// re-tapping cannot double-credit (both ways). Returns `true` only on a real
    /// transition, so the caller knows whether to raise the celebration overlay.
    @discardableResult
    func setCompletion(_ complete: Bool, in context: NSManagedObjectContext) -> Bool {
        guard isCompleted != complete else { return false }
        isCompleted = complete
        completedDate = complete ? Date() : nil
        verificationStatus = complete ? "verified" : "pending"

        // Canonical XP / level / streak / save / widget — credited exactly ONCE
        // per real transition (the guard above prevents re-firing for the same
        // state, both ways).
        let profile = UserProfile.fetchOrCreate(in: context)
        if complete {
            profile.registerCompletion(xp: Int(xpReward), in: context)
        } else {
            profile.unregisterCompletion(xp: Int(xpReward), in: context)
        }

        let goalID = goal?.id?.uuidString ?? ""
        let justCompletedGoal = complete ? (goal?.markCompletedIfAllStepsDone() ?? false) : false
        try? context.save()
        if complete, justCompletedGoal {
            Task { @MainActor in AdaptiveNotificationScheduler.handleGoalCompletion(goalID: goalID) }
        }
        return true
    }
}
