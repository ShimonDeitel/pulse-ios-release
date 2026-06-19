import SwiftUI
import CoreData

/// DEDICATED entry point for "Master a Skill" goals.
///
/// Pure skill-acquisition setup — name of the skill, where the user is today,
/// what mastery looks like, weekly time commitment, and learning style.
/// Hands the assembled Goal to `AIPulseGenerator` for the actual pulse plan.
struct MasterSkillGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState

    @State private var skillName: String = ""
    @State private var currentLevel: ProficiencyLevel = .none
    @State private var targetLevel: ProficiencyLevel = .conversational
    @State private var weeklyHours: Double = 5
    @State private var learningStyle: LearningStyle = .mixed
    @State private var targetWeeks: Double = 12
    @State private var motivation: Double = 8
    @State private var pulseCount: Double = 20

    @State private var isCreating: Bool = false
    @State private var showingAILoader: Bool = false
    @State private var showingFailureDialog: Bool = false
    @State private var pendingGoalID: NSManagedObjectID? = nil
    @State private var aiErrorDetail: String? = nil
    @State private var didCreateGoal: Bool = false

    enum ProficiencyLevel: String, CaseIterable, Identifiable {
        case none, beginner, intermediate, conversational, advanced, fluent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:           return "Never tried"
            case .beginner:       return "Beginner"
            case .intermediate:   return "Intermediate"
            case .conversational: return "Conversational"
            case .advanced:       return "Advanced"
            case .fluent:         return "Fluent / Pro"
            }
        }
    }

    enum LearningStyle: String, CaseIterable, Identifiable {
        case reading, video, practice, mixed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .reading:  return "Reading"
            case .video:    return "Video"
            case .practice: return "Hands-on practice"
            case .mixed:    return "Mix it up"
            }
        }
        var icon: String {
            switch self {
            case .reading:  return "book.fill"
            case .video:    return "play.rectangle.fill"
            case .practice: return "hand.tap.fill"
            case .mixed:    return "shuffle"
            }
        }
    }

    private var canCreate: Bool {
        !skillName.trimmingCharacters(in: .whitespaces).isEmpty && targetWeeks >= 1
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                    header
                    skillField
                    levelComparison
                    weeklyHoursSlider
                    targetWeeksSlider
                    learningStylePicker
                    motivationSlider
                    PulseCountSlider(count: $pulseCount, recommended: recommendedPulses)
                    createButton
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, 40)
            }
            .pulseScreen()
            .navigationTitle("Master a Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .overlay {
                if showingAILoader {
                    AIRoadmapBuildingOverlay(title: "Master a Skill").transition(.opacity)
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
            // Restore any saved Master-a-Skill draft so backing out and
            // reopening doesn't lose the skill name / levels / sliders / style.
            // Only override a default when a saved value actually exists.
            .onAppear {
                let f = DraftService.shared.draftFields(.skill)
                if let v = f["skillName"] { skillName = v }
                if let v = f["currentLevel"], let p = ProficiencyLevel(rawValue: v) { currentLevel = p }
                if let v = f["targetLevel"], let p = ProficiencyLevel(rawValue: v) { targetLevel = p }
                if let v = f["weeklyHours"], let n = Double(v) { weeklyHours = n }
                if let v = f["learningStyle"], let s = LearningStyle(rawValue: v) { learningStyle = s }
                if let v = f["targetWeeks"], let n = Double(v) { targetWeeks = n }
                if let v = f["motivation"], let n = Double(v) { motivation = n }
                if let v = f["pulseCount"], let n = Double(v) { pulseCount = n }
            }
            // Persist every user input the moment it changes so a draft never
            // loses state.
            .onChange(of: skillName)      { persistDraftFields() }
            .onChange(of: currentLevel)   { persistDraftFields() }
            .onChange(of: targetLevel)    { persistDraftFields() }
            .onChange(of: weeklyHours)    { persistDraftFields() }
            .onChange(of: learningStyle)  { persistDraftFields() }
            .onChange(of: targetWeeks)    { persistDraftFields() }
            .onChange(of: motivation)     { persistDraftFields() }
            .onChange(of: pulseCount)     { persistDraftFields() }
            // Leaving without finishing keeps the inputs in the draft; creating
            // the goal clears them (handled in runAI on success).
            .onDisappear { if !didCreateGoal { persistDraftFields() } }
        }
    }

    /// Persist the in-progress Master-a-Skill inputs into the draft so they
    /// survive backing out and are restored on resume. Numbers stored as Strings.
    private func persistDraftFields() {
        guard !didCreateGoal else { return }
        DraftService.shared.saveDraftFields(.skill, [
            "skillName": skillName,
            "currentLevel": currentLevel.rawValue,
            "targetLevel": targetLevel.rawValue,
            "weeklyHours": String(Int(weeklyHours)),
            "learningStyle": learningStyle.rawValue,
            "targetWeeks": String(Int(targetWeeks)),
            "motivation": String(Int(motivation)),
            "pulseCount": String(Int(pulseCount))
        ])
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(PulseColors.signal)
            Text("Master a Skill")
                .font(PulseTypography.headlineLarge)
                .foregroundColor(PulseColors.textPrimary)
                .headlineTracking()
        }
        .frame(maxWidth: .infinity)
    }

    private var skillField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("WHAT SKILL")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            TextField(
                "",
                text: $skillName,
                prompt: Text("e.g. Conversational Spanish, Photoshop, classical guitar")
                    .foregroundColor(PulseColors.textTertiary)
            )
            .font(PulseTypography.bodyLarge)
            .foregroundColor(PulseColors.textPrimary)
            .padding(14)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var levelComparison: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("WHERE YOU ARE  →  WHERE YOU WANT TO BE")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)

            HStack(spacing: 10) {
                levelMenu(selection: $currentLevel, caption: "Current")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PulseColors.muted)
                levelMenu(selection: $targetLevel, caption: "Target")
            }
        }
    }

    private func levelMenu(selection: Binding<ProficiencyLevel>, caption: String) -> some View {
        Menu {
            ForEach(ProficiencyLevel.allCases) { level in
                Button(level.label) { selection.wrappedValue = level }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(caption.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PulseColors.muted)
                HStack {
                    Text(selection.wrappedValue.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PulseColors.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PulseColors.muted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var weeklyHoursSlider: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("WEEKLY HOURS")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(weeklyHours)) hr/wk")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $weeklyHours, in: 1...40, step: 1)
                .tint(PulseColors.signal)
            Text("Be honest. 1 hour/day consistent beats 20 once.")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var targetWeeksSlider: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("TIMELINE")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(targetWeeks)) \(Int(targetWeeks) == 1 ? "week" : "weeks")")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $targetWeeks, in: 1...52, step: 1)
                .tint(PulseColors.signal)
        }
    }

    private var learningStylePicker: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("HOW YOU LEARN BEST")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            HStack(spacing: 8) {
                ForEach(LearningStyle.allCases) { style in
                    Button {
                        learningStyle = style
                        PulseHaptics.light()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: style.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(learningStyle == style ? .white : PulseColors.signal)
                            Text(style.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(learningStyle == style ? .white : PulseColors.ink)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(learningStyle == style ? PulseColors.signal : PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
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
        if skillName.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the skill you want to master." }
        if targetWeeks < 1 { return "Pick a timeline of at least 1 week." }
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
                Text(isCreating ? "Building your study plan…" : "Build the Plan")
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
        goal.title = "Master \(skillName.trimmingCharacters(in: .whitespaces))"
        goal.goalDescription = """
        Skill: \(skillName).
        Current level: \(currentLevel.label).
        Target level: \(targetLevel.label).
        Learning style: \(learningStyle.label).
        Commitment: \(Int(weeklyHours)) hours/week for \(Int(targetWeeks)) weeks.
        """
        goal.category = GoalCategory.learning.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.createdAt = Date()
        goal.deadline = Calendar.current.date(byAdding: .weekOfYear, value: Int(targetWeeks), to: Date())
        goal.motivationLevel = Int16(motivation)
        goal.availableTimePerDay = Float(weeklyHours * 60 / 7)
        goal.skillLevel = mapToSkillLevel(currentLevel).rawValue
        goal.urgencyLevel = UrgencyLevel.medium.rawValue

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
                    // Master-a-Skill start is blank (and onDisappear won't re-save).
                    didCreateGoal = true
                    DraftService.shared.clearDraftFields(.skill)
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

    private func mapToSkillLevel(_ p: ProficiencyLevel) -> SkillLevel {
        switch p {
        case .none, .beginner: return .beginner
        case .intermediate, .conversational: return .intermediate
        case .advanced, .fluent: return .advanced
        }
    }
}
