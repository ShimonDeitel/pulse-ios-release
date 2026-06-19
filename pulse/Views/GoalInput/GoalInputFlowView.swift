import SwiftUI

struct GoalInputFlowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var viewModel = GoalInputViewModel()

    /// Set once the goal is actually created, so the draft-persisting
    /// .onChange/.onDisappear hooks stop re-saving fields we just cleared.
    @State private var didCreateGoal = false

    /// Title-bar text based on the goal flavor.
    private var navTitle: String {
        switch viewModel.flavor {
        case "skill":   return "New Skill"
        case "project": return "New Project"
        case "money":   return "Make Money"
        default:        return "New Goal"
        }
    }

    /// Restore the in-progress "Anything Else" (.standard) draft so backing out
    /// and reopening doesn't reset the multi-step wizard to step 0 with empty
    /// fields. A fresh GoalInputViewModel() is built on every present, so without
    /// this the worst kind of draft loss happens. Only overrides a default when a
    /// saved value actually exists. Runs before applyPendingPrefill() so an
    /// explicit just-picked prefill still wins.
    private func restoreDraft() {
        let f = DraftService.shared.draftFields(.standard)
        guard !f.isEmpty else { return }
        if let v = f["title"] { viewModel.title = v }
        if let v = f["category"], let c = GoalCategory(rawValue: v) { viewModel.selectedCategory = c }
        if let v = f["deadline"], let d = ISO8601DateFormatter().date(from: v) { viewModel.deadline = d }
        if let v = f["motivationLevel"], let n = Double(v) { viewModel.motivationLevel = n }
        if let v = f["timePerDay"], let n = Double(v) { viewModel.timePerDay = n }
        if let v = f["skillLevel"], let s = SkillLevel(rawValue: v) { viewModel.skillLevel = s }
        if let v = f["currentProgressValue"], let n = Double(v) { viewModel.currentProgressValue = n }
        if let v = f["obstacles"] { viewModel.obstacles = v }
        if let v = f["whatDidYouDo"] { viewModel.whatDidYouDo = v }
        if let v = f["whatNeedHelp"] { viewModel.whatNeedHelp = v }
        // Restore a sensible step: never the AI-analysis step (we don't persist
        // analysis results), and never out of range for the current flow.
        if let v = f["currentStep"], let n = Int(v) {
            viewModel.currentStep = max(0, min(n, viewModel.analysisStepIndex - 1))
        }
    }

    /// Persist every user-entered field into the .standard draft so leaving the
    /// wizard before finishing never loses state. Numbers/dates/enums encoded as
    /// Strings; dates as ISO-8601, enums by rawValue.
    private func persistDraft() {
        guard !didCreateGoal else { return }
        DraftService.shared.saveDraftFields(.standard, [
            "title": viewModel.title,
            "category": viewModel.selectedCategory.rawValue,
            "deadline": ISO8601DateFormatter().string(from: viewModel.deadline),
            "motivationLevel": String(Int(viewModel.motivationLevel)),
            "timePerDay": String(Int(viewModel.timePerDay)),
            "skillLevel": viewModel.skillLevel.rawValue,
            "currentProgressValue": String(Int(viewModel.currentProgressValue)),
            "obstacles": viewModel.obstacles,
            "whatDidYouDo": viewModel.whatDidYouDo,
            "whatNeedHelp": viewModel.whatNeedHelp,
            "currentStep": String(viewModel.currentStep)
        ])
    }

    /// Apply any pending prefill (e.g. money style picked before opening).
    /// Called once on appear.
    private func applyPendingPrefill() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "pulse_pending_money_style"),
           let style = MoneyStyle(rawValue: raw) {
            viewModel.title = "Make money via \(style.displayName.lowercased())"
            viewModel.selectedCategory = .finance
            defaults.removeObject(forKey: "pulse_pending_money_style")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                HStack(spacing: PulseSpacing.sm) {
                    ForEach(0..<viewModel.totalSteps, id: \.self) { index in
                        Capsule()
                            .fill(index <= viewModel.currentStep ? PulseColors.primary : PulseColors.surfaceContainer)
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, PulseSpacing.sm)

                TabView(selection: $viewModel.currentStep) {
                    // Standard sequence: Basics → Resources → Obstacles → (Progress?) → Analysis
                    // Project flow inserts a "Project Details" step right after Basics.
                    GoalBasicsStep(viewModel: viewModel).tag(0)
                    if viewModel.flavor == "project" {
                        GoalProjectStep(viewModel: viewModel).tag(1)
                        GoalResourcesStep(viewModel: viewModel).tag(2)
                        GoalObstaclesStep(viewModel: viewModel).tag(3)
                        if viewModel.hasProgressContext {
                            GoalProgressContextStep(viewModel: viewModel).tag(4)
                            GoalAIAnalysisView(viewModel: viewModel).tag(5)
                        } else {
                            GoalAIAnalysisView(viewModel: viewModel).tag(4)
                        }
                    } else {
                        GoalResourcesStep(viewModel: viewModel).tag(1)
                        GoalObstaclesStep(viewModel: viewModel).tag(2)
                        if viewModel.hasProgressContext {
                            GoalProgressContextStep(viewModel: viewModel).tag(3)
                            GoalAIAnalysisView(viewModel: viewModel).tag(4)
                        } else {
                            GoalAIAnalysisView(viewModel: viewModel).tag(3)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Navigation buttons
                HStack {
                    if viewModel.currentStep > 0 && viewModel.currentStep < viewModel.analysisStepIndex {
                        Button("Back".localized) {
                            withAnimation(PulseAnimations.standard) { viewModel.currentStep -= 1 }
                        }
                        .buttonStyle(M3OutlinedButton())
                    }

                    Spacer()

                    if viewModel.currentStep < viewModel.analysisStepIndex - 1 {
                        Button("Next".localized) {
                            withAnimation(PulseAnimations.standard) { viewModel.currentStep += 1 }
                        }
                        .buttonStyle(M3FilledButton())
                        .disabled(!viewModel.canProceed)
                    } else if viewModel.currentStep == viewModel.analysisStepIndex - 1 {
                        Button("Analyze".localized) {
                            withAnimation(PulseAnimations.standard) { viewModel.currentStep = viewModel.analysisStepIndex }
                            Task { await viewModel.analyzeGoal() }
                        }
                        .buttonStyle(M3FilledButton())
                    } else if viewModel.analysisResult != nil {
                        Button("Start Mission".localized) {
                            let _ = viewModel.saveGoal(context: viewContext)
                            // Blocked by the Free 1-active-goal cap — show the
                            // upgrade sheet instead of dismissing. (AI is free;
                            // Pro = unlimited goals.)
                            if viewModel.showingUpgrade { return }
                            // Goal created — clear the saved draft and stop the
                            // .onChange/.onDisappear hooks from re-saving it.
                            didCreateGoal = true
                            DraftService.shared.clearDraftFields(.standard)
                            PulseHaptics.success()
                            dismiss()
                        }
                        .buttonStyle(M3FilledButton())
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, PulseSpacing.screenEdge)
            }
            .pulseScreen()
            .dismissKeyboardOnTap()
            .sheet(isPresented: $viewModel.showingUpgrade) { UpgradeView() }
            .onAppear {
                restoreDraft()
                applyPendingPrefill()
            }
            // Persist every user input the moment it changes so the wizard never
            // loses state when backed out of. (.onChange does not fire on the
            // initial appear, so it can't clobber the draft before restoreDraft.)
            .onChange(of: viewModel.title)                { persistDraft() }
            .onChange(of: viewModel.selectedCategory)     { persistDraft() }
            .onChange(of: viewModel.deadline)             { persistDraft() }
            .onChange(of: viewModel.motivationLevel)      { persistDraft() }
            .onChange(of: viewModel.timePerDay)           { persistDraft() }
            .onChange(of: viewModel.skillLevel)           { persistDraft() }
            .onChange(of: viewModel.currentProgressValue) { persistDraft() }
            .onChange(of: viewModel.obstacles)            { persistDraft() }
            .onChange(of: viewModel.whatDidYouDo)         { persistDraft() }
            .onChange(of: viewModel.whatNeedHelp)         { persistDraft() }
            .onChange(of: viewModel.currentStep)          { persistDraft() }
            .onDisappear { persistDraft() }
            .navigationTitle(navTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel".localized) { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            // toolbar follows system color scheme
        }
    }
}

struct GoalBasicsStep: View {
    @Bindable var viewModel: GoalInputViewModel
    @FocusState private var titleFocused: Bool

    /// Per-flavor placeholder so the field shows the kind of goal that fits.
    private var titlePlaceholder: String {
        switch viewModel.flavor {
        case "skill":   return "e.g. Master Photoshop".localized
        case "project": return "e.g. Finish college".localized
        default:        return "e.g. Learn Spanish".localized
        }
    }

    /// Big headline at the top of step 1, tailored to the flavor.
    private var headlineText: String {
        switch viewModel.flavor {
        case "skill":   return "What's the skill?".localized
        case "project": return "What's the project?".localized
        case "money":   return "What's the money goal?".localized
        default:        return "What's your goal?".localized
        }
    }

    /// Label above the title text field.
    private var titleFieldLabel: String {
        switch viewModel.flavor {
        case "skill":   return "SKILL".localized
        case "project": return "PROJECT".localized
        default:        return "GOAL TITLE".localized
        }
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                Text(headlineText)
                    .font(PulseTypography.headlineLarge)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text(titleFieldLabel)
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()
                    TextField("", text: $viewModel.title, prompt: Text(titlePlaceholder).foregroundColor(PulseColors.textTertiary))
                        .font(PulseTypography.bodyLarge)
                        .foregroundColor(PulseColors.textPrimary)
                        .focused($titleFocused)
                        .padding(PulseSpacing.lg)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: PulseSpacing.md) {
                    Text("CATEGORY")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: PulseSpacing.sm) {
                        ForEach(GoalCategory.allCases) { category in
                            Button {
                                viewModel.selectedCategory = category
                                PulseHaptics.light()
                            } label: {
                                HStack(spacing: PulseSpacing.xs) {
                                    Image(systemName: category.iconName)
                                        .font(.system(size: 14))
                                    Text(category.displayName)
                                        .font(PulseTypography.labelMedium)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundColor(viewModel.selectedCategory == category ? PulseColors.onPrimary : PulseColors.textSecondary)
                                .padding(.horizontal, PulseSpacing.md)
                                .padding(.vertical, PulseSpacing.sm + 2)
                                .frame(maxWidth: .infinity)
                                .background(viewModel.selectedCategory == category ? category.color : PulseColors.surfaceContainer)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(viewModel.selectedCategory == category ? Color.clear : PulseColors.outlineVariant, lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("DEADLINE")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()
                    DatePicker("", selection: $viewModel.deadline, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(PulseColors.primary)
                }

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    HStack {
                        Text("MOTIVATION")
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(PulseColors.textTertiary)
                            .eyebrowTracking()
                        Spacer()
                        Text("\(Int(viewModel.motivationLevel))/10")
                            .font(PulseTypography.monoCaption)
                            .foregroundColor(PulseColors.primary)
                    }
                    Slider(value: $viewModel.motivationLevel, in: 1...10, step: 1)
                        .tint(PulseColors.primary)
                }
            }
            .padding(PulseSpacing.screenEdge)
        }
    }
}

struct GoalResourcesStep: View {
    @Bindable var viewModel: GoalInputViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                Text("Your Resources")
                    .font(PulseTypography.headlineLarge)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    HStack {
                        Text("TIME PER DAY")
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(PulseColors.textTertiary)
                            .eyebrowTracking()
                        Spacer()
                        Text("\(Int(viewModel.timePerDay)) min")
                            .font(PulseTypography.monoCaption)
                            .foregroundColor(PulseColors.primary)
                    }
                    Slider(value: $viewModel.timePerDay, in: 15...240, step: 15)
                        .tint(PulseColors.primary)
                }

                VStack(alignment: .leading, spacing: PulseSpacing.md) {
                    Text("SKILL LEVEL")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PulseSpacing.sm) {
                            ForEach(SkillLevel.allCases) { level in
                                Button {
                                    viewModel.skillLevel = level
                                    PulseHaptics.light()
                                } label: {
                                    Text(level.displayName)
                                        .font(PulseTypography.labelMedium)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .foregroundColor(viewModel.skillLevel == level ? PulseColors.onPrimary : PulseColors.textSecondary)
                                        .padding(.horizontal, PulseSpacing.lg)
                                        .padding(.vertical, PulseSpacing.sm + 2)
                                        .background(viewModel.skillLevel == level ? PulseColors.primary : PulseColors.surfaceContainer)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(viewModel.skillLevel == level ? Color.clear : PulseColors.outlineVariant, lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    HStack {
                        Text("CURRENT PROGRESS")
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(PulseColors.textTertiary)
                            .eyebrowTracking()
                        Spacer()
                        Text("\(Int(viewModel.currentProgressValue))%")
                            .font(PulseTypography.monoCaption)
                            .foregroundColor(PulseColors.primary)
                    }
                    Slider(value: $viewModel.currentProgressValue, in: 0...100, step: 5)
                        .tint(PulseColors.primary)
                }
            }
            .padding(PulseSpacing.screenEdge)
        }
    }
}

struct GoalObstaclesStep: View {
    @Bindable var viewModel: GoalInputViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                Text("Potential Obstacles")
                    .font(PulseTypography.headlineLarge)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()

                Text("What might get in your way?")
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textSecondary)

                TextEditor(text: $viewModel.obstacles)
                    .font(PulseTypography.bodyLarge)
                    .foregroundColor(PulseColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(PulseSpacing.lg)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                            .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("COMMON OBSTACLES")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()

                    let commonObstacles = [
                        "Time management", "Lack of motivation", "Budget constraints",
                        "Skill gaps", "Procrastination", "External commitments",
                        "Fear of failure", "Perfectionism", "Inconsistent schedule",
                        "Lack of accountability", "Information overload", "Physical fatigue",
                        "Social pressure", "Self-doubt", "Distractions at home",
                        "Unclear next steps"
                    ]

                    FlowLayout(spacing: PulseSpacing.sm) {
                        ForEach(commonObstacles, id: \.self) { obstacle in
                            Button {
                                if !viewModel.obstacles.isEmpty { viewModel.obstacles += ", " }
                                viewModel.obstacles += obstacle
                                PulseHaptics.light()
                            } label: {
                                Text(obstacle)
                                    .font(PulseTypography.labelMedium)
                                    .foregroundColor(PulseColors.textSecondary)
                                    .padding(.horizontal, PulseSpacing.md)
                                    .padding(.vertical, PulseSpacing.sm)
                                    .background(PulseColors.surfaceContainer)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(PulseColors.outlineVariant, lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
            .padding(PulseSpacing.screenEdge)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

struct GoalProgressContextStep: View {
    @Bindable var viewModel: GoalInputViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("You're \(Int(viewModel.currentProgressValue))% there")
                        .font(PulseTypography.headlineLarge)
                        .foregroundColor(PulseColors.textPrimary)
                        .headlineTracking()

                    Text("Tell us about your progress so far so we can build the right plan for what's left.")
                        .font(PulseTypography.bodyMedium)
                        .foregroundColor(PulseColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("WHAT DID YOU DO SO FAR?")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()

                    TextEditor(text: $viewModel.whatDidYouDo)
                        .font(PulseTypography.bodyLarge)
                        .foregroundColor(PulseColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                        .padding(PulseSpacing.lg)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("WHAT DO YOU NEED HELP WITH?")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()

                    TextEditor(text: $viewModel.whatNeedHelp)
                        .font(PulseTypography.bodyLarge)
                        .foregroundColor(PulseColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                        .padding(PulseSpacing.lg)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                        )
                }
            }
            .padding(PulseSpacing.screenEdge)
        }
    }
}

struct GoalAIAnalysisView: View {
    @Bindable var viewModel: GoalInputViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: PulseSpacing.xxl) {
                if viewModel.isAnalyzing {
                    // Animated loading screen with scrolling status messages
                    VStack(spacing: 32) {
                        Spacer(minLength: 40)

                        // Pulsing EKG animation
                        ZStack {
                            Circle()
                                .stroke(PulseColors.surfaceContainer, lineWidth: 3)
                                .frame(width: 120, height: 120)

                            Circle()
                                .stroke(PulseColors.primary.opacity(0.3), lineWidth: 3)
                                .frame(width: 120, height: 120)
                                .scaleEffect(1.0 + CGFloat(viewModel.currentLoadingMessage % 2) * 0.1)
                                .opacity(0.6)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: viewModel.currentLoadingMessage)

                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 40, weight: .ultraLight))
                                .foregroundColor(PulseColors.primary)
                                .symbolEffect(.pulse, options: .repeating)
                        }

                        // Current status message
                        VStack(spacing: 12) {
                            Text(viewModel.loadingMessages.indices.contains(viewModel.currentLoadingMessage) ? viewModel.loadingMessages[viewModel.currentLoadingMessage] : "Building your plan...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(PulseColors.textPrimary)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut(duration: 0.4), value: viewModel.currentLoadingMessage)
                                .id(viewModel.currentLoadingMessage)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))

                            // Progress dots
                            HStack(spacing: 6) {
                                ForEach(0..<min(viewModel.loadingMessages.count, 13), id: \.self) { i in
                                    Circle()
                                        .fill(i <= viewModel.currentLoadingMessage ? PulseColors.primary : PulseColors.surfaceContainer)
                                        .frame(width: 6, height: 6)
                                        .animation(.easeInOut(duration: 0.3), value: viewModel.currentLoadingMessage)
                                }
                            }
                        }

                        // Scrolling log of completed steps
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0...viewModel.currentLoadingMessage, id: \.self) { i in
                                if viewModel.loadingMessages.indices.contains(i) {
                                    HStack(spacing: 8) {
                                        Image(systemName: i < viewModel.currentLoadingMessage ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                            .font(.system(size: 11))
                                            .foregroundColor(i < viewModel.currentLoadingMessage ? PulseColors.primary.opacity(0.6) : PulseColors.primary)
                                            .symbolEffect(.rotate, options: .repeating, value: i == viewModel.currentLoadingMessage)

                                        Text(viewModel.loadingMessages[i])
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(i < viewModel.currentLoadingMessage ? PulseColors.textTertiary : PulseColors.textSecondary)
                                    }
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(PulseColors.surfaceContainer.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .animation(.easeInOut(duration: 0.4), value: viewModel.currentLoadingMessage)

                        Spacer(minLength: 40)
                    }
                } else if let error = viewModel.analysisError, viewModel.analysisResult == nil {
                    VStack(spacing: PulseSpacing.lg) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundColor(PulseColors.warning)
                        Text("Analysis Failed")
                            .font(PulseTypography.titleLarge)
                            .foregroundColor(PulseColors.textPrimary)
                        Text(error)
                            .font(PulseTypography.bodyMedium)
                            .foregroundColor(PulseColors.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await viewModel.analyzeGoal() }
                        }
                        .buttonStyle(M3TonalButton())
                    }
                } else if let result = viewModel.analysisResult {
                    analysisResultView(result)
                }
            }
            .padding(PulseSpacing.screenEdge)
        }
    }

    @ViewBuilder
    private func analysisResultView(_ result: GoalAnalysisResult) -> some View {
        // Probability score
        VStack(spacing: PulseSpacing.sm) {
            ProgressRingView(
                progress: Double(result.probabilityScore) / 100.0,
                size: 100,
                lineWidth: 8,
                color: result.probabilityScore >= 70 ? PulseColors.success : result.probabilityScore >= 40 ? PulseColors.warning : PulseColors.danger
            )
            Text("Success Probability")
                .font(PulseTypography.labelMedium)
                .foregroundColor(PulseColors.textSecondary)
        }

        // Assessment card
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("Assessment")
                .font(PulseTypography.titleMedium)
                .foregroundColor(PulseColors.textPrimary)
            Text(result.realismAssessment)
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.textSecondary)
                .lineSpacing(2)
        }
        .padding(PulseSpacing.cardPadding)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )

        // Fastest path card
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack(spacing: PulseSpacing.sm) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(PulseColors.warning)
                Text("Fastest Path")
                    .font(PulseTypography.titleMedium)
                    .foregroundColor(PulseColors.textPrimary)
            }
            Text(result.fastestPath)
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.textSecondary)
                .lineSpacing(2)
        }
        .padding(PulseSpacing.cardPadding)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )

        // Roadmap preview
        VStack(alignment: .leading, spacing: PulseSpacing.md) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(PulseColors.primary)
                Text("Your Roadmap")
                    .font(PulseTypography.titleMedium)
                    .foregroundColor(PulseColors.textPrimary)
                Spacer()
                Text("\(result.steps.count) pulses")
                    .font(PulseTypography.monoCaption)
                    .foregroundColor(PulseColors.primary)
                    .padding(.horizontal, PulseSpacing.sm)
                    .padding(.vertical, PulseSpacing.xxs + 1)
                    .background(PulseColors.primary.opacity(0.08))
                    .clipShape(Capsule())
            }

            ForEach(result.steps.prefix(5), id: \.stepNumber) { step in
                HStack(alignment: .top, spacing: PulseSpacing.sm + 2) {
                    Text("\(step.stepNumber)")
                        .font(PulseTypography.monoCaption)
                        .foregroundColor(PulseColors.primary)
                        .frame(width: 24, height: 24)
                        .background(PulseColors.primary.opacity(0.08))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                        Text(step.title)
                            .font(PulseTypography.labelLargeEmphasized)
                            .foregroundColor(PulseColors.textPrimary)
                        Text(step.howTo)
                            .font(PulseTypography.bodySmall)
                            .foregroundColor(PulseColors.textTertiary)
                            .lineLimit(2)
                    }
                }
            }

            if result.steps.count > 5 {
                Text("+ \(result.steps.count - 5) more pulses...")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
                    .padding(.leading, 34)
            }
        }
        .padding(PulseSpacing.cardPadding)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )

        if !result.skillGaps.isEmpty {
            VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                Text("Skill Gaps")
                    .font(PulseTypography.titleMedium)
                    .foregroundColor(PulseColors.textPrimary)
                ForEach(result.skillGaps, id: \.self) { gap in
                    HStack(spacing: PulseSpacing.sm) {
                        Circle()
                            .fill(PulseColors.warning)
                            .frame(width: 6, height: 6)
                        Text(gap)
                            .font(PulseTypography.bodyMedium)
                            .foregroundColor(PulseColors.textSecondary)
                    }
                }
            }
            .padding(PulseSpacing.cardPadding)
            .background(PulseColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
            )
        }
    }
}
