import SwiftUI

/// Picks the right detail screen based on the goal's category.
/// Transformation goals get the workout + meals experience.
/// Everything else uses the standard pulse-list GoalDetailView.
struct GoalDetailRouter: View {
    @ObservedObject var goal: Goal

    /// Whether this goal was built with one of the dedicated AI flows. AI is free
    /// for everyone now, so this no longer affects access — kept only as a marker.
    private var isProGoal: Bool {
        goal.category == "transformation" || ProGoalRegistry.isPro(goal.id?.uuidString)
    }

    var body: some View {
        // AI is free for everyone, so `hasAIGeneration` is always true and this
        // branch is unreachable — no goal is ever locked behind a tier. Kept as a
        // defensive fallback in case AI ever becomes unavailable.
        if !SubscriptionManager.shared.hasAIGeneration && isProGoal {
            LockedFeatureView(
                title: "AI temporarily unavailable",
                message: "This goal's AI plan can't be reached right now. Try again in a moment — or add your own steps manually.",
                icon: "lock.fill"
            )
            .navigationTitle(goal.titleValue)
            .navigationBarTitleDisplayMode(.inline)
        } else if goal.category == "transformation" {
            TransformationDetailView(goal: goal)
        } else if goal.category == "workout" {
            // No-AI manual workout plan — its own lean, free detail screen.
            CustomWorkoutDetailView(goal: goal)
        } else {
            GoalDetailView(goal: goal)
        }
    }
}
