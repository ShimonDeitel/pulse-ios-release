import SwiftUI

struct ActiveGoalCard: View {
    @ObservedObject var goal: Goal
    /// When true (a Pro/AI goal viewed on Free), shows a small inline gold PRO
    /// lock badge by the subtitle — instead of an overlay that collides with the
    /// progress ring.
    var showsProLock: Bool = false
    @State private var appear = false

    var body: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.lg) {
            HStack(spacing: PulseSpacing.md) {
                Image(systemName: goal.categoryEnum.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(goal.categoryEnum.color)
                    .frame(width: 40, height: 40)
                    .background(goal.categoryEnum.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: M3Shapes.small, style: .continuous))

                VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                    Text(goal.titleValue)
                        .font(PulseTypography.titleMedium)
                        .foregroundColor(PulseColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(goal.daysRemaining) days left")
                            .font(PulseTypography.labelSmall)
                            .foregroundColor(goal.daysRemaining < 7 ? PulseColors.danger : PulseColors.textTertiary)
                        if showsProLock { ProLockPill() }
                    }
                }

                Spacer()

                ProgressRingView(
                    progress: goal.progressPercentage,
                    size: 44,
                    lineWidth: 4,
                    color: goal.categoryEnum.color
                )
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PulseColors.surfaceContainer)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(goal.categoryEnum.color)
                        .frame(width: appear ? geo.size.width * goal.progressPercentage : 0, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                HStack(spacing: PulseSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(PulseColors.success)
                    Text("\(goal.completedTodaysTasks)/\(goal.todaysTasks.count) today")
                        .font(PulseTypography.labelSmall)
                        .foregroundColor(PulseColors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
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
        .padding(.horizontal, PulseSpacing.screenEdge)
        .onAppear {
            withAnimation(PulseAnimations.reveal.delay(0.1)) {
                appear = true
            }
        }
    }
}
