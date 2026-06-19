import SwiftUI
import CoreData

struct GoalsListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)],
        animation: .default
    )
    private var goals: FetchedResults<Goal>

    @State private var draftService = DraftService.shared
    @State private var renamingGoal: Goal?
    @State private var renameText: String = ""
    // Shown when a Free user taps a goal that's locked behind Pro (e.g. an
    // AI-built goal after downgrading) — routes to the paywall instead of the
    // goal's detail/complete UI.
    @State private var showingUpgrade = false
    // Resume-draft reality check: a resumed draft is still creating a goal,
    // so the AI / medical / financial disclaimer must still appear before
    // the goal is built (the picker path already does this).
    @State private var resumingType: GoalType?

    var body: some View {
        Group {
            if goals.isEmpty && draftService.drafts.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: PulseSpacing.md) {
                        if !draftService.drafts.isEmpty { draftsSection }
                        ForEach(goals) { goal in goalCard(goal) }
                        if goals.isEmpty { newGoalButton }   // drafts present, no active goals
                    }
                    .padding(.top, PulseSpacing.lg)
                    .padding(.bottom, PulseSpacing.section)
                }
            }
        }
        .pulseScreen()
        .navigationTitle("Goals".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingUpgrade) { UpgradeView() }
        .fullScreenCover(item: $resumingType) { type in
            GoalRealityCheckView(
                goalType: type,
                onContinue: {
                    resumingType = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        openCreationFlow(for: type)
                    }
                },
                onCancel: { resumingType = nil }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.showingGoalTypePicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(PulseColors.ink)
                }
            }
        }
        .alert("Rename Goal".localized, isPresented: Binding(
            get: { renamingGoal != nil },
            set: { if !$0 { renamingGoal = nil } }
        )) {
            TextField("Goal name".localized, text: $renameText)
            Button("Cancel".localized, role: .cancel) { renamingGoal = nil }
            Button("Save".localized) {
                if let goal = renamingGoal {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        goal.title = trimmed
                        try? viewContext.save()
                        WidgetDataService.shared.updateWidgets(context: viewContext)
                        PulseHaptics.success()
                    }
                }
                renamingGoal = nil
            }
        }
        // Clear any draft that has since become a real goal.
        .onAppear { draftService.reconcile(against: Array(goals)) }
        .onChange(of: goals.count) { _, _ in draftService.reconcile(against: Array(goals)) }
    }

    // MARK: - Drafts

    private var draftsSection: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                Text("DRAFTS".localized)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
            }
            .foregroundColor(PulseColors.muted)
            .padding(.horizontal, PulseSpacing.screenEdge)

            ForEach(draftService.drafts) { draft in
                draftRow(draft)
            }
        }
    }

    private func draftRow(_ draft: GoalDraft) -> some View {
        let type = GoalType(rawValue: draft.typeRaw)
        return Button { resume(draft) } label: {
            HStack(spacing: PulseSpacing.lg) {
                Image(systemName: type?.iconName ?? "target")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(PulseColors.signal)
                    .frame(width: 44, height: 44)
                    .background(PulseColors.signal.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: M3Shapes.medium, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue \(type?.displayName ?? "goal")")
                        .font(PulseTypography.titleMedium)
                        .foregroundColor(PulseColors.textPrimary)
                    Text("Draft · started \(draft.startedAt.formatted(.relative(presentation: .named)))")
                        .font(PulseTypography.bodySmall)
                        .foregroundColor(PulseColors.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16))
                    .foregroundColor(PulseColors.textTertiary)
            }
            .padding(PulseSpacing.cardPadding)
            .background(PulseColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .strokeBorder(PulseColors.signal.opacity(0.30), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .contextMenu {
            Button { resume(draft) } label: { Label("Continue".localized, systemImage: "arrow.right") }
            Button(role: .destructive) {
                draftService.remove(draft.id)
                PulseHaptics.light()
            } label: { Label("Delete draft".localized, systemImage: "trash") }
        }
    }

    /// Re-open the creation flow for a draft's goal type. The draft stays until
    /// the goal is actually created (then `reconcile` removes it).
    private var activeGoalCount: Int { goals.filter { $0.statusEnum == .active }.count }

    private func resume(_ draft: GoalDraft) {
        guard let type = GoalType(rawValue: draft.typeRaw) else { return }
        // Free is capped at 1 active goal — finishing a draft would create a 2nd.
        guard SubscriptionManager.shared.canCreateGoal(currentCount: activeGoalCount) else {
            PulseHaptics.medium(); showingUpgrade = true; return
        }
        PulseHaptics.medium()
        // Show the reality-check disclaimer for resumed drafts too — they
        // are still creating a goal, so the medical / AI / financial framing
        // must appear (mirrors the GoalTypePicker → realityCheck → flow path).
        resumingType = type
    }

    private func openCreationFlow(for type: GoalType) {
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

    // MARK: - Goals

    @ViewBuilder
    private func goalCard(_ goal: Goal) -> some View {
        Group {
            if goal.isLockedForCurrentTier {
                // Locked Pro goal on Free: tapping opens the paywall, not the
                // goal's detail/complete UI. The card shows a clean inline PRO
                // badge by the subtitle (no overlay colliding with the ring).
                Button { showingUpgrade = true } label: {
                    ActiveGoalCard(goal: goal, showsProLock: true)
                }
            } else {
                NavigationLink(destination: GoalDetailRouter(goal: goal)) {
                    ActiveGoalCard(goal: goal)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = goal.title ?? ""
                renamingGoal = goal
            } label: {
                Label("Rename".localized, systemImage: "pencil")
            }
            Button(role: .destructive) {
                let goalID = goal.id?.uuidString ?? ""
                AdaptiveNotificationScheduler.cancelGoalNotifications(goalID: goalID)
                if !goalID.isEmpty {
                    Task { try? await FirestoreSyncService.shared.deleteGoal(goalId: goalID) }
                }
                viewContext.delete(goal)
                try? viewContext.save()
                WidgetDataService.shared.updateWidgets(context: viewContext)
                AdaptiveNotificationScheduler.shared.refreshFromSettings()
            } label: {
                Label("Delete".localized, systemImage: "trash")
            }
        }
    }

    // MARK: - Empty states

    private var newGoalButton: some View {
        Button {
            appState.showingGoalTypePicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(PulseColors.muted.opacity(0.7))
                Text("New Goal".localized)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PulseColors.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .strokeBorder(PulseColors.muted.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var emptyState: some View {
        VStack(spacing: PulseSpacing.lg) {
            Spacer()
            Image(systemName: "target")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(PulseColors.muted)
            Text("No active goals".localized)
                .font(PulseTypography.titleMedium)
                .foregroundColor(PulseColors.muted)
            newGoalButton
            Spacer()
        }
    }
}
