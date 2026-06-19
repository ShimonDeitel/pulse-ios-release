import SwiftUI
import CoreData

/// DEDICATED entry point for "Big Project" goals.
///
/// Long-horizon, multi-phase work — finish college, write a book, ship a
/// product, defend a thesis. Captures end state, deliverables, phases,
/// complexity, and timeline so `AIPulseGenerator` can produce a roadmap
/// that breaks the work into logical phases instead of daily checklist items.
struct BigProjectGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState

    @State private var projectName: String = ""
    @State private var endState: String = ""
    @State private var deliverables: String = ""
    @State private var phases: String = ""
    @State private var complexity: Double = 5
    @State private var targetWeeks: Double = 12
    @State private var weeklyHours: Double = 10
    @State private var motivation: Double = 7
    @State private var pulseCount: Double = 20

    @State private var isCreating: Bool = false
    @State private var showingAILoader: Bool = false
    @State private var showingFailureDialog: Bool = false
    @State private var pendingGoalID: NSManagedObjectID? = nil
    @State private var aiErrorDetail: String? = nil
    @State private var didCreateGoal: Bool = false

    private var canCreate: Bool {
        !projectName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !endState.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                    header
                    nameField
                    endStateField
                    deliverablesField
                    phasesField
                    complexitySlider
                    timeRow
                    motivationSlider
                    PulseCountSlider(count: $pulseCount, recommended: recommendedPulses)
                    createButton
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, 40)
            }
            .pulseScreen()
            .navigationTitle("Big Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .overlay {
                if showingAILoader {
                    AIRoadmapBuildingOverlay(title: "Big Project").transition(.opacity)
                }
                if showingFailureDialog {
                    AIRoadmapFailureDialog(
                        onRetry: { retryAI() },
                        onCancel: { cancelCreation() },
                        errorDetail: aiErrorDetail
                    ).transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showingAILoader)
            .animation(.easeInOut(duration: 0.25), value: showingFailureDialog)
            // Restore any saved Big-Project draft so backing out and reopening
            // doesn't lose the name / end state / deliverables / phases / sliders.
            // Only override a default when a saved value actually exists.
            .onAppear {
                let f = DraftService.shared.draftFields(.project)
                if let v = f["projectName"] { projectName = v }
                if let v = f["endState"] { endState = v }
                if let v = f["deliverables"] { deliverables = v }
                if let v = f["phases"] { phases = v }
                if let v = f["complexity"], let n = Double(v) { complexity = n }
                if let v = f["targetWeeks"], let n = Double(v) { targetWeeks = n }
                if let v = f["weeklyHours"], let n = Double(v) { weeklyHours = n }
                if let v = f["motivation"], let n = Double(v) { motivation = n }
                if let v = f["pulseCount"], let n = Double(v) { pulseCount = n }
            }
            // Persist every user input the moment it changes so a draft never
            // loses state.
            .onChange(of: projectName)  { persistDraftFields() }
            .onChange(of: endState)     { persistDraftFields() }
            .onChange(of: deliverables) { persistDraftFields() }
            .onChange(of: phases)       { persistDraftFields() }
            .onChange(of: complexity)   { persistDraftFields() }
            .onChange(of: targetWeeks)  { persistDraftFields() }
            .onChange(of: weeklyHours)  { persistDraftFields() }
            .onChange(of: motivation)   { persistDraftFields() }
            .onChange(of: pulseCount)   { persistDraftFields() }
            // Leaving without finishing keeps the inputs in the draft; creating
            // the goal clears them (handled in runAI on success).
            .onDisappear { if !didCreateGoal { persistDraftFields() } }
        }
    }

    /// Persist the in-progress Big-Project inputs into the draft so they survive
    /// backing out and are restored on resume. Numbers stored as Strings.
    private func persistDraftFields() {
        guard !didCreateGoal else { return }
        DraftService.shared.saveDraftFields(.project, [
            "projectName": projectName,
            "endState": endState,
            "deliverables": deliverables,
            "phases": phases,
            "complexity": String(Int(complexity)),
            "targetWeeks": String(Int(targetWeeks)),
            "weeklyHours": String(Int(weeklyHours)),
            "motivation": String(Int(motivation)),
            "pulseCount": String(Int(pulseCount))
        ])
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(PulseColors.signal)
            Text("Big Project")
                .font(PulseTypography.headlineLarge)
                .foregroundColor(PulseColors.textPrimary)
                .headlineTracking()
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("PROJECT NAME")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            TextField(
                "",
                text: $projectName,
                prompt: Text("e.g. Write & publish my novel").foregroundColor(PulseColors.textTertiary)
            )
            .font(PulseTypography.bodyLarge)
            .foregroundColor(PulseColors.textPrimary)
            .padding(14)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var endStateField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("WHAT DOES \"DONE\" LOOK LIKE")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            TextField(
                "",
                text: $endState,
                prompt: Text("e.g. Manuscript published on Amazon with 10 reviews")
                    .foregroundColor(PulseColors.textTertiary),
                axis: .vertical
            )
            .font(PulseTypography.bodyMedium)
            .foregroundColor(PulseColors.textPrimary)
            .lineLimit(2...4)
            .padding(14)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var deliverablesField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("KEY DELIVERABLES")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            TextField(
                "",
                text: $deliverables,
                prompt: Text("e.g. outline, draft 1, draft 2, edit, cover, publish")
                    .foregroundColor(PulseColors.textTertiary),
                axis: .vertical
            )
            .font(PulseTypography.bodyMedium)
            .foregroundColor(PulseColors.textPrimary)
            .lineLimit(2...4)
            .padding(14)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Comma-separated. Skip if you want the AI to figure them out.")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var phasesField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("PHASES (OPTIONAL)")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            TextField(
                "",
                text: $phases,
                prompt: Text("e.g. research, plan, build, polish, ship")
                    .foregroundColor(PulseColors.textTertiary),
                axis: .vertical
            )
            .font(PulseTypography.bodyMedium)
            .foregroundColor(PulseColors.textPrimary)
            .lineLimit(2...3)
            .padding(14)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var complexitySlider: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("COMPLEXITY")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(complexity))/10")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $complexity, in: 1...10, step: 1)
                .tint(PulseColors.signal)
            Text("1 = a weekend hack, 10 = a multi-year endeavor.")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var timeRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TIMELINE")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Text("\(Int(targetWeeks)) wk")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.signal)
                Slider(value: $targetWeeks, in: 1...104, step: 1)
                    .tint(PulseColors.signal)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("HOURS/WEEK")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Text("\(Int(weeklyHours)) hr")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.signal)
                Slider(value: $weeklyHours, in: 1...60, step: 1)
                    .tint(PulseColors.signal)
            }
        }
    }

    private var motivationSlider: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("MOTIVATION")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(motivation))/10")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $motivation, in: 1...10, step: 1)
                .tint(PulseColors.signal)
        }
    }

    private var missingRequirement: String? {
        if projectName.trimmingCharacters(in: .whitespaces).isEmpty { return "Name your project to continue." }
        if endState.trimmingCharacters(in: .whitespaces).isEmpty { return "Describe what \"done\" looks like." }
        return nil
    }

    private var createButton: some View {
        VStack(spacing: 8) {
        if let missing = missingRequirement, !isCreating {
            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundColor(PulseColors.textTertiary)
                Text(missing).font(PulseTypography.bodySmall).foregroundColor(PulseColors.textSecondary)
                Spacer(minLength: 0)
            }
        }
        Button {
            createGoal()
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isCreating ? "Mapping the project…" : "Build the Roadmap")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canCreate ? PulseColors.signal : PulseColors.muted.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canCreate || isCreating)
        }
    }

    // MARK: - Goal creation

    /// Blocking AI creation flow — see MakeMoneyGoalView for the rationale.
    private func createGoal() {
        guard canCreate, !isCreating else { return }
        isCreating = true
        PulseHaptics.medium()

        let goal = Goal(context: viewContext)
        goal.id = UUID()
        goal.title = projectName.trimmingCharacters(in: .whitespaces)
        var description = "Done = \(endState.trimmingCharacters(in: .whitespaces))."
        if !deliverables.trimmingCharacters(in: .whitespaces).isEmpty {
            description += " Deliverables: \(deliverables)."
        }
        if !phases.trimmingCharacters(in: .whitespaces).isEmpty {
            description += " Phases: \(phases)."
        }
        description += " Complexity: \(Int(complexity))/10."
        description += " Commitment: \(Int(weeklyHours)) hr/week for \(Int(targetWeeks)) weeks."
        goal.goalDescription = description

        goal.category = GoalCategory.career.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.createdAt = Date()
        goal.deadline = Calendar.current.date(byAdding: .weekOfYear, value: Int(targetWeeks), to: Date())
        goal.motivationLevel = Int16(motivation)
        goal.availableTimePerDay = Float(weeklyHours * 60 / 7)
        goal.skillLevel = SkillLevel.intermediate.rawValue
        goal.urgencyLevel = complexity >= 8 ? UrgencyLevel.high.rawValue : UrgencyLevel.medium.rawValue

        let profile = UserProfile.fetchOrCreate(in: viewContext)
        goal.userProfile = profile

        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)
        pendingGoalID = goal.objectID
        showingAILoader = true
        runAI()
    }

    private var recommendedPulses: Int {
        AIPulseGenerator.recommendedPulseCount(
            motivation: Int(motivation),
            timePerDayMinutes: max(15, Int(weeklyHours * 60 / 7)),
            daysUntilDeadline: max(7, Int(targetWeeks) * 7)
        )
    }

    private func runAI() {
        guard let goalID = pendingGoalID else { return }
        Task {
            let ok = await AIPulseGenerator.shared.generatePulsesAndWait(forGoalWithID: goalID, requestedCount: Int(pulseCount))
            await MainActor.run {
                showingAILoader = false
                if ok {
                    PulseHaptics.success()
                    // The goal is now real — drop the saved draft so a future
                    // Big-Project start is blank (and onDisappear won't re-save).
                    didCreateGoal = true
                    DraftService.shared.clearDraftFields(.project)
                    if let goal = try? viewContext.existingObject(with: goalID) as? Goal {
                        Task { try? await FirestoreSyncService.shared.syncGoal(goal) }
                    }
                    AdaptiveNotificationScheduler.shared.refreshFromSettings()
                    dismiss()
                } else {
                    aiErrorDetail = AIPulseGenerator.shared.lastError
                    showingFailureDialog = true
                }
            }
        }
    }

    private func retryAI() {
        showingFailureDialog = false
        showingAILoader = true
        runAI()
    }

    private func cancelCreation() {
        showingFailureDialog = false
        if let goalID = pendingGoalID,
           let goal = try? viewContext.existingObject(with: goalID) as? Goal {
            viewContext.delete(goal)
            try? viewContext.save()
            WidgetDataService.shared.updateWidgets(context: viewContext)
        }
        pendingGoalID = nil
        isCreating = false
    }
}
