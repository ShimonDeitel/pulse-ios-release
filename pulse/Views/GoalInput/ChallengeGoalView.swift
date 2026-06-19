import SwiftUI
import CoreData

/// DEDICATED entry point for "Challenge" goals.
///
/// Short-term sprint (7 / 14 / 30 day). One repeated daily action, fixed
/// duration, intensity slider. No AI roadmap call — pulses are pre-generated
/// directly from the daily action since the structure is uniform.
struct ChallengeGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var title = ""
    @State private var selectedDuration = 7
    @State private var dailyAction = ""
    @State private var motivationLevel: Double = 7
    @State private var isCreating = false

    private let durations = [7, 14, 30]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(PulseColors.signal)
                        Text("New Challenge")
                            .font(PulseTypography.headlineLarge)
                            .foregroundColor(PulseColors.textPrimary)
                            .headlineTracking()
                        Text("Short-term sprint to push your limits")
                            .font(PulseTypography.bodyMedium)
                            .foregroundColor(PulseColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Challenge Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHALLENGE NAME")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)
                        TextField("", text: $title, prompt: Text("e.g. Run every day").foregroundColor(PulseColors.textTertiary))
                            .font(PulseTypography.bodyLarge)
                            .foregroundColor(PulseColors.textPrimary)
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Duration
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DURATION")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)

                        HStack(spacing: 10) {
                            ForEach(durations, id: \.self) { days in
                                Button {
                                    selectedDuration = days
                                    PulseHaptics.light()
                                } label: {
                                    Text("\(days) Days")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(selectedDuration == days ? PulseColors.onPrimary : PulseColors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(selectedDuration == days ? PulseColors.mono : PulseColors.surfaceContainer)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    // Daily Action
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DAILY ACTION")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)
                        TextField("", text: $dailyAction, prompt: Text("What will you do every day?").foregroundColor(PulseColors.textTertiary))
                            .font(PulseTypography.bodyLarge)
                            .foregroundColor(PulseColors.textPrimary)
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Motivation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("INTENSITY")
                                .font(PulseTypography.eyebrow)
                                .eyebrowTracking()
                                .foregroundColor(PulseColors.textTertiary)
                            Spacer()
                            Text("\(Int(motivationLevel))/10")
                                .font(PulseTypography.monoCaption)
                                .foregroundColor(PulseColors.signal)
                        }
                        Slider(value: $motivationLevel, in: 1...10, step: 1)
                            .tint(PulseColors.signal)
                    }

                    // Create button
                    Button {
                        createChallenge()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                            Text(isCreating ? "Creating..." : "Start \(selectedDuration)-Day Challenge")
                        }
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(PulseColors.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PulseColors.mono)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(title.isEmpty || isCreating)
                    .opacity(title.isEmpty ? 0.5 : 1)
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, 40)
            }
            .pulseScreen()
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            // Resume a saved Challenge draft: restore every typed/selected field
            // (name, duration, daily action, intensity) so backing out and
            // re-entering never loses what you'd entered.
            .onAppear {
                let f = DraftService.shared.draftFields(.challenge)
                if let t = f["title"], !t.isEmpty { title = t }
                if let d = f["duration"], let n = Int(d), durations.contains(n) { selectedDuration = n }
                if let a = f["dailyAction"] { dailyAction = a }
                if let m = f["motivation"], let n = Double(m) { motivationLevel = n }
            }
            // Persist each field the moment it changes so a draft never goes stale.
            .onChange(of: title) { persistDraftFields() }
            .onChange(of: selectedDuration) { persistDraftFields() }
            .onChange(of: dailyAction) { persistDraftFields() }
            .onChange(of: motivationLevel) { persistDraftFields() }
        }
    }

    /// Persist the in-progress Challenge inputs into the draft so they survive
    /// backing out and are restored on resume. Cleared once the challenge is created.
    private func persistDraftFields() {
        guard !isCreating else { return }
        DraftService.shared.saveDraftFields(.challenge, [
            "title": title,
            "duration": String(selectedDuration),
            "dailyAction": dailyAction,
            "motivation": String(Int(motivationLevel))
        ])
    }

    private func createChallenge() {
        isCreating = true
        let goal = Goal(context: viewContext)
        goal.id = UUID()
        goal.title = title
        goal.goalDescription = "\(selectedDuration)-day challenge: \(dailyAction.isEmpty ? title : dailyAction)"
        goal.category = GoalCategory.personal.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.deadline = Calendar.current.date(byAdding: .day, value: selectedDuration, to: Date())
        goal.currentProgress = 0
        goal.motivationLevel = Int16(motivationLevel)
        goal.createdAt = Date()

        let profile = UserProfile.fetchOrCreate(in: viewContext)
        goal.userProfile = profile

        let action = dailyAction.isEmpty ? title : dailyAction
        for day in 1...selectedDuration {
            let task = DailyTask(context: viewContext)
            task.id = UUID()
            task.title = "Day \(day): \(action)"
            task.howToDescription = "Complete today's challenge: \(action)"
            task.proofDescription = "Mark as done when completed"
            task.proofType = "text"
            task.stepNumber = Int16(clamping: day)
            task.sortOrder = Int16(clamping: day)
            task.estimatedMinutes = 30
            task.xpReward = 10
            task.isCompleted = false
            task.verificationStatus = "pending"
            task.scheduledDate = Calendar.current.date(byAdding: .day, value: day - 1, to: Date())
            task.goal = goal
        }

        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)

        // The challenge is now a real goal — drop its saved draft fields so a future
        // Challenge starts blank and onChange re-saves won't resurrect it.
        DraftService.shared.clearDraftFields(.challenge)

        Task { try? await FirestoreSyncService.shared.syncGoal(goal) }

        AdaptiveNotificationScheduler.shared.refreshFromSettings()
        PulseHaptics.heavy()
        dismiss()
    }
}
