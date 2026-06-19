import SwiftUI
import CoreData

/// "Your Progress" — a live momentum dashboard reached from the Progress
/// quick action. Every number here is real Core Data: level/XP, streaks,
/// pulses completed, completion %, focus time, and per-goal progress rings.
/// No fake or placeholder values.
struct ProgressInsightsView: View {
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [])
    private var profiles: FetchedResults<UserProfile>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)])
    private var allGoals: FetchedResults<Goal>

    private var profile: UserProfile? { profiles.first }
    private var activeGoals: [Goal] { allGoals.filter { $0.statusEnum == .active } }

    // MARK: Aggregates (all derived from live data)

    private var totalCompletedPulses: Int { allGoals.reduce(0) { $0 + $1.completedSteps } }
    private var totalPulses: Int { allGoals.reduce(0) { $0 + $1.totalSteps } }
    private var overallCompletion: Double {
        totalPulses > 0 ? Double(totalCompletedPulses) / Double(totalPulses) : 0
    }
    private var totalFocusMinutes: Int { allGoals.reduce(0) { $0 + $1.totalFocusMinutes } }
    private var totalFocusSessions: Int { allGoals.reduce(0) { $0 + $1.focusSessionsArray.count } }
    private var completedGoalsCount: Int { allGoals.filter { $0.statusEnum == .completed }.count }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroCard
                    statsGrid
                    goalsSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 12)
            }
            .pulseScreen()
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(PulseColors.signal)
                }
            }
        }
    }

    // MARK: - Hero (level / XP / streaks)

    private var heroCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LEVEL")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)
                    Text("\(profile?.levelValue ?? 1)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(PulseColors.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    streakChip(icon: "flame.fill", value: Int(profile?.currentStreak ?? 0), label: "day streak")
                    streakChip(icon: "trophy.fill", value: Int(profile?.longestStreak ?? 0), label: "best ever")
                }
            }

            // XP progress toward next level
            VStack(spacing: 7) {
                HStack {
                    Text("\(Int(profile?.totalXP ?? 0)) XP")
                        .font(PulseTypography.labelSmall)
                        .foregroundColor(PulseColors.ink)
                    Spacer()
                    Text("Level \(Int((profile?.currentLevel ?? 1) + 1)) at \(Int(profile?.xpForNextLevel ?? 100)) XP")
                        .font(PulseTypography.labelSmall)
                        .foregroundColor(PulseColors.muted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PulseColors.surfaceContainer)
                        Capsule()
                            .fill(PulseColors.signal)
                            .frame(width: max(6, geo.size.width * (profile?.xpProgress ?? 0)))
                    }
                }
                .frame(height: 9)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
    }

    private func streakChip(icon: String, value: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(PulseColors.signal)
            Text("\(value)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(PulseColors.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PulseColors.muted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(PulseColors.surfaceContainer)
        .clipShape(Capsule())
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            statTile(icon: "bolt.fill", value: "\(totalCompletedPulses)", caption: totalPulses > 0 ? "of \(totalPulses) pulses done" : "pulses done")
            statTile(icon: "checkmark.circle.fill", value: "\(Int(overallCompletion * 100))%", caption: "overall complete")
            statTile(icon: "target", value: "\(activeGoals.count)", caption: activeGoals.count == 1 ? "active goal" : "active goals")
            statTile(icon: "flag.checkered", value: "\(completedGoalsCount)", caption: completedGoalsCount == 1 ? "goal finished" : "goals finished")
            statTile(icon: "timer", value: focusTimeString(totalFocusMinutes), caption: "focus time")
            statTile(icon: "brain.head.profile", value: "\(totalFocusSessions)", caption: totalFocusSessions == 1 ? "focus session" : "focus sessions")
        }
    }

    private func statTile(icon: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PulseColors.signal)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(PulseColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(PulseColors.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
    }

    // MARK: - Per-goal progress

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOAL PROGRESS")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.muted)
                .padding(.top, 4)

            if activeGoals.isEmpty {
                emptyGoals
            } else {
                VStack(spacing: 10) {
                    ForEach(activeGoals, id: \.objectID) { goal in
                        goalRow(goal)
                    }
                }
            }
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        let progress = goal.totalSteps > 0
            ? Double(goal.completedSteps) / Double(goal.totalSteps)
            : goal.progressPercentage

        return HStack(spacing: 14) {
            ProgressRingView(progress: progress, size: 52, lineWidth: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.titleValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PulseColors.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(goal.completedSteps) / \(goal.totalSteps) pulses")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PulseColors.muted)
                    if goal.deadline != nil {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(PulseColors.muted)
                        Text(goal.daysRemaining == 0 ? "due today" : "\(goal.daysRemaining)d left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(goal.daysRemaining <= 3 ? PulseColors.danger : PulseColors.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PulseColors.hair, lineWidth: 0.5)
        )
    }

    private var emptyGoals: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(PulseColors.muted)
            Text("No active goals yet")
                .font(PulseTypography.titleMedium)
                .foregroundColor(PulseColors.ink)
            Text("Create a goal and start completing pulses — your momentum shows up here.")
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func focusTimeString(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
