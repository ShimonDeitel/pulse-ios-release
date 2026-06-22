import SwiftUI
import CoreData

/// DEDICATED entry point for "Make Money" goals.
///
/// Pure financial setup — target income amount, monetization style (freelance,
/// e-commerce, SaaS, etc.), timeline, and whether the user wants a one-shot
/// lump sum or a recurring monthly run-rate. Hands the assembled Goal off to
/// `AIPulseGenerator` which builds the actual pulses.
///
/// Lives in its own file so the money flow can evolve independently of skill,
/// project, transformation, habit, and challenge flows.
struct MakeMoneyGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState

    // MARK: - Inputs
    @State private var targetAmountText: String = "5000"
    @State private var earningModel: EarningModel = .recurringMonthly
    @State private var moneyStyle: MoneyStyle = .freelance
    @State private var timelineMonths: Double = 3
    @State private var weeklyHours: Double = 10
    @State private var startingFromZero: Bool = true
    @State private var pulseCount: Double = 20

    @State private var isCreating: Bool = false
    @State private var showingAILoader: Bool = false
    @State private var showingFailureDialog: Bool = false
    @State private var pendingGoalID: NSManagedObjectID? = nil
    @State private var aiErrorDetail: String? = nil
    @State private var didCreateGoal: Bool = false
    /// Set when creation is blocked by the Free 1-active-goal cap, so the paywall
    /// is presented instead of a second active goal being created. (AI is free;
    /// Pro = unlimited goals.)
    @State private var showingUpgrade: Bool = false

    enum EarningModel: String, CaseIterable, Identifiable {
        case recurringMonthly = "monthly"   // $X/mo run-rate
        case lumpSum = "lump"               // earn $X total
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recurringMonthly: return "Monthly run-rate"
            case .lumpSum:          return "Total amount"
            }
        }
        var icon: String {
            switch self {
            case .recurringMonthly: return "arrow.triangle.2.circlepath"
            case .lumpSum:          return "dollarsign.circle"
            }
        }
    }

    private var targetAmount: Double {
        Double(targetAmountText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canCreate: Bool {
        targetAmount >= 100 && timelineMonths >= 1
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                    header
                    targetField
                    earningModelPicker
                    moneyStyleGrid
                    timelineSlider
                    weeklyHoursSlider
                    fromZeroToggle
                    PulseCountSlider(count: $pulseCount, recommended: recommendedPulses)
                    createButton
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, 40)
            }
            .pulseScreen()
            .navigationTitle("Make Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .overlay {
                if showingAILoader {
                    AIRoadmapBuildingOverlay(title: "Make Money")
                        .transition(.opacity)
                }
                if showingFailureDialog {
                    AIRoadmapFailureDialog(
                        onRetry: { retryAI() },
                        onCancel: { cancelCreation() },
                        errorDetail: aiErrorDetail
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showingAILoader)
            .animation(.easeInOut(duration: 0.25), value: showingFailureDialog)
            .sheet(isPresented: $showingUpgrade) { UpgradeView() }
            // Restore any saved Make-Money draft so backing out and reopening
            // doesn't lose the target / model / style / sliders. Only override a
            // default when a saved value actually exists.
            .onAppear {
                let f = DraftService.shared.draftFields(.money)
                if let v = f["targetAmount"] { targetAmountText = v }
                if let v = f["earningModel"], let m = EarningModel(rawValue: v) { earningModel = m }
                if let v = f["moneyStyle"], let s = MoneyStyle(rawValue: v) { moneyStyle = s }
                if let v = f["timelineMonths"], let n = Double(v) { timelineMonths = n }
                if let v = f["weeklyHours"], let n = Double(v) { weeklyHours = n }
                if let v = f["startingFromZero"] { startingFromZero = (v == "true") }
                if let v = f["pulseCount"], let n = Double(v) { pulseCount = n }
            }
            // Persist every user input the moment it changes so a draft never
            // loses state.
            .onChange(of: targetAmountText) { persistDraftFields() }
            .onChange(of: earningModel)     { persistDraftFields() }
            .onChange(of: moneyStyle)       { persistDraftFields() }
            .onChange(of: timelineMonths)   { persistDraftFields() }
            .onChange(of: weeklyHours)      { persistDraftFields() }
            .onChange(of: startingFromZero) { persistDraftFields() }
            .onChange(of: pulseCount)       { persistDraftFields() }
            // Leaving without finishing keeps the inputs in the draft; creating
            // the goal clears them (handled in runAI on success).
            .onDisappear { if !didCreateGoal { persistDraftFields() } }
        }
    }

    /// Persist the in-progress Make-Money inputs into the draft so they survive
    /// backing out and are restored on resume. Numbers stored as Strings.
    private func persistDraftFields() {
        guard !didCreateGoal else { return }
        DraftService.shared.saveDraftFields(.money, [
            "targetAmount": targetAmountText,
            "earningModel": earningModel.rawValue,
            "moneyStyle": moneyStyle.rawValue,
            "timelineMonths": String(Int(timelineMonths)),
            "weeklyHours": String(Int(weeklyHours)),
            "startingFromZero": startingFromZero ? "true" : "false",
            "pulseCount": String(Int(pulseCount))
        ])
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(PulseColors.signal)
            Text("Make Money")
                .font(PulseTypography.headlineLarge)
                .foregroundColor(PulseColors.textPrimary)
                .headlineTracking()
        }
        .frame(maxWidth: .infinity)
    }

    private var targetField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text(earningModel == .recurringMonthly ? "TARGET MONTHLY INCOME" : "TARGET TOTAL")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            HStack(spacing: 10) {
                Text("$")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
                TextField("5000", text: $targetAmountText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.ink)
            }
            .padding(14)
            .background(PulseColors.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(earningModel == .recurringMonthly
                 ? "What you want to be earning every single month."
                 : "Total dollars in your pocket by the deadline.")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var earningModelPicker: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("MODEL")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            HStack(spacing: 10) {
                ForEach(EarningModel.allCases) { model in
                    Button {
                        earningModel = model
                        PulseHaptics.light()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: model.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(earningModel == model ? .white : PulseColors.signal)
                            Text(model.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(earningModel == model ? .white : PulseColors.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(earningModel == model ? PulseColors.signal : PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var moneyStyleGrid: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("HOW WILL YOU EARN IT")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MoneyStyle.allCases) { style in
                    Button {
                        moneyStyle = style
                        PulseHaptics.light()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: style.icon)
                                .font(.system(size: 14))
                                .foregroundColor(moneyStyle == style ? .white : PulseColors.signal)
                            Text(style.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(moneyStyle == style ? .white : PulseColors.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(moneyStyle == style ? PulseColors.signal : PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(moneyStyle.description)
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
                .padding(.top, 2)
        }
    }

    private var timelineSlider: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("TIMELINE")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(timelineMonths)) \(Int(timelineMonths) == 1 ? "month" : "months")")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $timelineMonths, in: 1...24, step: 1)
                .tint(PulseColors.signal)
            Text("How long do you give yourself to hit it?")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var weeklyHoursSlider: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("HOURS PER WEEK")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(weeklyHours)) hr")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $weeklyHours, in: 1...80, step: 1)
                .tint(PulseColors.signal)
        }
    }

    private var fromZeroToggle: some View {
        Toggle(isOn: $startingFromZero) {
            VStack(alignment: .leading, spacing: 2) {
                Text("STARTING FROM SCRATCH")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Text(startingFromZero
                     ? "Brand new to this — pulses will start with the absolute basics."
                     : "Already earning — pulses will skip the 101 and push to the next level."
                )
                .font(.system(size: 12))
                .foregroundColor(PulseColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(PulseColors.signal)
    }

    private var missingRequirement: String? {
        if targetAmount < 100 { return "Enter a target of at least $100." }
        if timelineMonths < 1 { return "Pick a timeline of at least 1 month." }
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
                Text(isCreating ? "Building your playbook…" : "Build the Roadmap")
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

    /// Goal creation now BLOCKS on the AI for a real personalized roadmap.
    /// No more fallback-template seeding masquerading as "the AI did it".
    /// Flow: create goal → show AI loader → await real pulses → dismiss.
    /// If AI hard-fails, show the recovery dialog so the user picks
    /// (retry / use starter plan / cancel) instead of being silently dropped
    /// on generic content.
    private func createGoal() {
        guard canCreate, !isCreating else { return }

        // Authoritative goal-cap backstop at the save site. AI is free for
        // everyone; this enforces only the Free 1-active-goal cap (Pro = unlimited
        // goals). A Free user already at the cap gets the paywall, not a 2nd goal.
        guard SubscriptionManager.shared.canCreateGoal(in: viewContext) else {
            PulseHaptics.medium()
            showingUpgrade = true
            return
        }

        isCreating = true
        PulseHaptics.medium()

        // 1. Create the goal entity itself (no pulses yet — AI will fill them).
        let goal = Goal(context: viewContext)
        goal.id = UUID()
        goal.title = makeTitle()
        goal.goalDescription = makeDescription()
        goal.category = GoalCategory.finance.rawValue
        goal.status = GoalStatus.active.rawValue
        goal.createdAt = Date()
        goal.deadline = Calendar.current.date(byAdding: .month, value: Int(timelineMonths), to: Date())
        goal.currentProgress = 0
        goal.aiProbabilityScore = 0
        goal.motivationLevel = 8
        goal.availableTimePerDay = Float(weeklyHours * 60 / 7)
        goal.skillLevel = (startingFromZero ? SkillLevel.beginner : SkillLevel.intermediate).rawValue
        goal.urgencyLevel = UrgencyLevel.medium.rawValue

        let profile = UserProfile.fetchOrCreate(in: viewContext)
        goal.userProfile = profile

        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)
        pendingGoalID = goal.objectID

        // 2. Show the loader and await real AI pulses.
        showingAILoader = true
        runAI()
    }

    private var recommendedPulses: Int {
        AIPulseGenerator.recommendedPulseCount(
            motivation: 8,
            timePerDayMinutes: max(15, Int(weeklyHours * 60 / 7)),
            daysUntilDeadline: max(7, Int(timelineMonths) * 30)
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
                    // Make-Money start is blank (and onDisappear won't re-save).
                    didCreateGoal = true
                    DraftService.shared.clearDraftFields(.money)
                    // Fire Firestore sync inline on MainActor (the URLSession
                    // await suspends without blocking the UI). Spawning a
                    // Task.detached with a Goal managed object would crash —
                    // NSManagedObject access is undefined off-context.
                    if let goal = try? viewContext.existingObject(with: goalID) as? Goal {
                        Task { try? await FirestoreSyncService.shared.syncGoal(goal) }
                    }
                    AdaptiveNotificationScheduler.shared.refreshFromSettings()
                    dismiss()
                } else {
                    // AI failed — let the user choose what to do.
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

    /// User backed out entirely — delete the empty goal so we don't leave
    /// orphan records in Core Data.
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

    private func makeTitle() -> String {
        let amount = Int(targetAmount).formatted(.number)
        switch earningModel {
        case .recurringMonthly:
            return "$\(amount)/mo via \(moneyStyle.displayName.lowercased())"
        case .lumpSum:
            return "Earn $\(amount) with \(moneyStyle.displayName.lowercased())"
        }
    }

    private func makeDescription() -> String {
        let amount = Int(targetAmount).formatted(.number)
        let timeline = "\(Int(timelineMonths)) months"
        let weekly = "\(Int(weeklyHours)) hr/week"
        let start = startingFromZero ? "starting from zero" : "already earning"
        switch earningModel {
        case .recurringMonthly:
            return "Hit $\(amount)/month recurring via \(moneyStyle.displayName.lowercased()). Timeline: \(timeline). Available time: \(weekly). Status: \(start)."
        case .lumpSum:
            return "Earn $\(amount) total via \(moneyStyle.displayName.lowercased()). Timeline: \(timeline). Available time: \(weekly). Status: \(start)."
        }
    }
}

