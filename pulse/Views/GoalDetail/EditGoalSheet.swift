import SwiftUI
import CoreData

/// Full edit sheet for an existing goal — title, category, deadline,
/// motivation, time-per-day, obstacles. Save pushes to Core Data and Firestore.
struct EditGoalSheet: View {
    @ObservedObject var goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var title: String = ""
    @State private var category: GoalCategory = .personal
    @State private var deadline: Date = Date()
    @State private var motivation: Double = 7
    @State private var timePerDay: Double = 30
    @State private var obstacles: String = ""

    // Change Plan — freeform instructions that rebuild the whole roadmap via AI.
    @State private var changeInstructions: String = ""
    @State private var rebuilding: Bool = false
    @State private var rebuildError: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field("TITLE") {
                        TextField("Goal title", text: $title)
                            .font(.system(size: 16, weight: .medium))
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    field("CATEGORY") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                            ForEach(GoalCategory.allCases) { cat in
                                Button {
                                    category = cat
                                    PulseHaptics.light()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.iconName)
                                            .font(.system(size: 12))
                                        Text(cat.displayName)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(category == cat ? .white : PulseColors.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(category == cat ? PulseColors.signal : PulseColors.surfaceContainer)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    field("DEADLINE") {
                        DatePicker("", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(PulseColors.signal)
                    }

                    field("MOTIVATION  ·  \(Int(motivation))/10") {
                        Slider(value: $motivation, in: 1...10, step: 1)
                            .tint(PulseColors.signal)
                    }

                    field("TIME PER DAY  ·  \(Int(timePerDay)) min") {
                        Slider(value: $timePerDay, in: 5...240, step: 5)
                            .tint(PulseColors.signal)
                    }

                    field("OBSTACLES (OPTIONAL)") {
                        TextField("What might get in your way?", text: $obstacles, axis: .vertical)
                            .font(.system(size: 14))
                            .lineLimit(2...4)
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        save()
                    } label: {
                        Text("Save Changes")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(canSave ? PulseColors.signal : PulseColors.muted.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!canSave)

                    // AI rebuild is free for everyone (hasAIGeneration is always
                    // true); wrapper kept for future gating / AI-unavailable case.
                    if SubscriptionManager.shared.hasAIGeneration {
                    Divider().background(PulseColors.hair).padding(.vertical, 4)

                    // -- Change the plan (AI rebuild from your own instructions) --
                    field("CHANGE THE PLAN") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tell the AI how you want your plan to look — focus areas, pace, format, anything — and it rebuilds your pulses from scratch.")
                                .font(.system(size: 12))
                                .foregroundColor(PulseColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            TextField("e.g. Make it more aggressive, focus on cold outreach, fewer admin tasks…",
                                      text: $changeInstructions, axis: .vertical)
                                .font(.system(size: 14))
                                .lineLimit(3...6)
                                .padding(14)
                                .background(PulseColors.surfaceContainer)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            if let err = rebuildError {
                                Text(err)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(PulseColors.signal)
                            }
                            Button {
                                rebuildPlan()
                            } label: {
                                HStack {
                                    if rebuilding { ProgressView().tint(.white) }
                                    Image(systemName: "wand.and.stars")
                                    Text(rebuilding ? "Rebuilding your plan…" : "Rebuild plan with AI")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(canRebuild ? PulseColors.signal : PulseColors.muted.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(!canRebuild)
                        }
                    }
                    } // end Change Plan (AI rebuild — free for all tiers)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.vertical, 16)
            }
            .pulseScreen()
            .dismissKeyboardOnTap()
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canRebuild: Bool {
        !rebuilding && !changeInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() {
        title = goal.titleValue
        category = goal.categoryEnum
        deadline = goal.deadline ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        motivation = Double(goal.motivationLevel)
        timePerDay = Double(goal.availableTimePerDay)
        if timePerDay <= 0 { timePerDay = 30 }
        obstacles = goal.obstacles ?? ""
    }

    /// Persist the edited fields to Core Data without dismissing.
    private func persistFields() {
        goal.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.category = category.rawValue
        goal.deadline = deadline
        goal.motivationLevel = Int16(motivation)
        goal.availableTimePerDay = Float(timePerDay)
        goal.obstacles = obstacles.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.updatedAt = Date()
        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)
        AdaptiveNotificationScheduler.shared.refreshFromSettings()
    }

    private func save() {
        persistFields()
        PulseHaptics.success()
        Task.detached(priority: .utility) {
            try? await FirestoreSyncService.shared.syncGoal(goal)
        }
        dismiss()
    }

    /// Rebuild the whole roadmap from the user's freeform instructions. Saves
    /// the edited fields first, then asks the AI for a fresh plan that REPLACES
    /// the current pulses. AI-only — on failure we surface the error and keep
    /// the existing plan intact.
    private func rebuildPlan() {
        persistFields()
        rebuildError = nil
        rebuilding = true
        let instructions = changeInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingCount = max(12, (goal.dailyTasks as? Set<DailyTask>)?.count ?? 20)
        let objectID = goal.objectID
        Task {
            let ok = await AIPulseGenerator.shared.generatePulsesAndWait(
                forGoalWithID: objectID,
                requestedCount: existingCount,
                extraInstructions: instructions
            )
            await MainActor.run {
                rebuilding = false
                if ok {
                    PulseHaptics.success()
                    dismiss()
                } else {
                    rebuildError = AIPulseGenerator.shared.lastError ?? "Couldn't rebuild the plan. Try again."
                }
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.muted)
            content()
        }
    }
}
