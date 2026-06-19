import SwiftUI
import CoreData

struct GoalDetailView: View {
    @ObservedObject var goal: Goal
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var proofTask: DailyTask?
    @State private var selectedTab = 0 // 0=Pulse, 1=List, 2=Schedule
    @State private var expandedStep: NSManagedObjectID?
    @State private var inlineAIQuestion: String = ""
    @State private var inlineAIResponse: String = ""
    @State private var isInlineAILoading = false
    @State private var showingRenameSheet = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingAddStep = false
    @State private var showingChat = false
    @State private var renameText: String = ""

    private var donePulses: Int { goal.completedSteps }
    private var totalPulses: Int { goal.totalSteps }
    private var dayOfGoal: Int {
        guard let start = goal.createdDate ?? Calendar.current.date(byAdding: .day, value: -goal.daysElapsed, to: Date()) else { return 1 }
        return max(1, Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 1)
    }
    private var totalDays: Int {
        guard let start = goal.createdDate ?? Calendar.current.date(byAdding: .day, value: -goal.daysElapsed, to: Date()),
              let deadline = goal.deadline else { return 30 }
        return max(1, Calendar.current.dateComponents([.day], from: start, to: deadline).day ?? 30)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                statsRow
                monitorCard
                tabSelector
                tabContent
            }
            .padding(.bottom, PulseSpacing.screenBottom)
        }
        .pulseScreen()
        .navigationTitle(goal.titleValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingChat = true
                    } label: {
                        Label("Chat about this goal", systemImage: "bubble.left.and.text.bubble.right.fill")
                    }
                    Button {
                        showingAddStep = true
                    } label: {
                        Label("Add a step", systemImage: "plus.circle")
                    }
                    Button {
                        renameText = goal.titleValue
                        showingRenameSheet = true
                    } label: {
                        Label("Rename".localized, systemImage: "pencil")
                    }
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Goal".localized, systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(PulseColors.ink)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("More options")
            }
        }
        .alert("Delete Goal", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                let goalID = goal.id?.uuidString ?? ""
                // 1. Stop this goal's reminders forever.
                AdaptiveNotificationScheduler.cancelGoalNotifications(goalID: goalID)
                // 2. Delete from the cloud so it can't resurface on another device.
                if !goalID.isEmpty {
                    Task { try? await FirestoreSyncService.shared.deleteGoal(goalId: goalID) }
                }
                // 3. Delete locally + refresh global nudges (so they don't keep
                //    referencing the deleted goal).
                viewContext.delete(goal)
                try? viewContext.save()
                // Refresh widgets so the deleted goal stops showing on the home screen.
                WidgetDataService.shared.updateWidgets(context: viewContext)
                AdaptiveNotificationScheduler.shared.refreshFromSettings()
                // Pop back to the Goals list — staying on a deleted goal crashes.
                DispatchQueue.main.async { dismiss() }
            }
        } message: {
            Text("This will permanently delete this goal and all its pulses. This cannot be undone.")
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameGoalSheet(goal: goal, text: $renameText)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingAddStep) {
            AddStepSheet(goal: goal)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditGoalSheet(goal: goal)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingChat) {
            NavigationStack { MentorChatView(fixedGoal: goal) }
                .environment(\.managedObjectContext, viewContext)
        }
        // Upload Proof sheet — item-based so the sheet binds to a concrete task,
        // no race condition between state set and sheet presentation.
        .sheet(item: $proofTask) { task in
            StepProofSheet(step: task, goal: goal)
                .environment(\.managedObjectContext, viewContext)
                .environment(appState)
        }
    }

    // MARK: - Header (Claude Design: ACTIVE · DAY X OF Y + title + stats)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status + day counter
            HStack(spacing: 8) {
                let isCompleted = goal.statusEnum == .completed
                Circle()
                    .fill(isCompleted ? PulseColors.gold : PulseColors.signal)
                    .frame(width: 8, height: 8)
                Text(isCompleted
                     ? "COMPLETED \u{00B7} \(totalDays) DAYS"
                     : "ACTIVE \u{00B7} DAY \(dayOfGoal) OF \(totalDays)")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.muted)
            }

            // Goal title
            Text(goal.titleValue)
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1.36)
                .foregroundColor(PulseColors.ink)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 12)
    }

    // MARK: - Stats Row (Claude Design: 3 big numbers)

    private var statsRow: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(donePulses)/\(totalPulses)")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-1.12)
                    .foregroundColor(PulseColors.ink)
                Text("PULSES".localized)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(goal.daysRemaining)d")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-1.12)
                    .foregroundColor(PulseColors.ink)
                Text("DAYS LEFT".localized)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(goal.aiProbabilityScore))%")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-1.12)
                    .foregroundColor(PulseColors.ink)
                Text("probability".localized.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 22)
    }

    // MARK: - Monitor Card (Claude Design: dark card with EKG trace)

    private var monitorCard: some View {
        VStack(spacing: 0) {
            // Header — honest progress label (not a heart-rate / vitals reading;
            // the app does not measure BPM). The pulse line below is decorative.
            HStack {
                Text("PROGRESS")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(1.26)
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Text("\(donePulses)/\(totalPulses) PULSES")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.signal)
            }
            .padding(.bottom, 10)

            // EKG Trace — compute beat positions as fractions [0..1]
            GeometryReader { geo in
                let pulsePositions: [CGFloat] = {
                    guard totalPulses > 0 && donePulses > 0 else { return [] }
                    return (0..<donePulses).map { i in
                        CGFloat(i + 1) / CGFloat(totalPulses)
                    }
                }()
                let prog = totalPulses > 0 ? CGFloat(donePulses) / CGFloat(totalPulses) : 0

                EKGTraceView(
                    width: geo.size.width,
                    height: 100,
                    beats: pulsePositions,
                    progress: prog,
                    color: PulseColors.signal,
                    animated: true
                )
            }
            .frame(height: 100)

            // Timeline labels
            HStack {
                Text(goal.startDateLabel)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text("NOW")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(goal.deadlineLabel)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(PulseColors.mono)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 20)
    }

    // MARK: - Tab Selector (Claude Design: Pulse | List | Schedule)

    private var tabSelector: some View {
        HStack(spacing: 6) {
            ForEach(["Pulse", "List", "Schedule"], id: \.self) { tab in
                let index = ["Pulse", "List", "Schedule"].firstIndex(of: tab) ?? 0
                Button {
                    withAnimation(PulseAnimations.standard) { selectedTab = index }
                } label: {
                    Text(tab.localized)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(selectedTab == index ? .white : PulseColors.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        // Unselected segments get a filled chip + stronger hairline so
                        // they read as clearly tappable against the cream background
                        // (a bare clear fill + 8% border was nearly invisible).
                        .background(selectedTab == index ? PulseColors.signal : PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedTab == index ? Color.clear : PulseColors.hairStrong, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 24)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: pulseTimelineTab
        case 1: pulseListTab
        case 2: scheduleTab
        default: pulseTimelineTab
        }
    }

    // MARK: - Pulse Timeline (with expandable instructions + inline AI)

    private var pulseTimelineTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(totalPulses) PULSES \u{00B7} \(goal.daysRemaining) DAYS LEFT")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.muted)
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 20)
                .padding(.bottom, 14)

            // Timeline
            VStack(spacing: 0) {
                ForEach(goal.allSteps, id: \.objectID) { step in
                    let done = step.isCompleted
                    let isCurrent = step.stepNumber == Int32(goal.currentStepIndex + 1)
                    let isToday = isStepToday(step)
                    let isExpanded = expandedStep == step.objectID

                    HStack(alignment: .top, spacing: 14) {
                        // Timeline node
                        VStack(spacing: 0) {
                            if step.stepNumber > 1 {
                                Rectangle()
                                    .fill(done ? PulseColors.mono : PulseColors.hair)
                                    .frame(width: 1.5, height: 6)
                            }

                            Circle()
                                .fill(done ? PulseColors.mono : (isToday || isCurrent) ? PulseColors.signal : PulseColors.cream)
                                .overlay(
                                    Circle()
                                        .stroke(done || isToday || isCurrent ? Color.clear : PulseColors.muted.opacity(0.5), lineWidth: 1.5)
                                )
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if done {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    } else if isToday || isCurrent {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 6, height: 6)
                                    }
                                }

                            if step.stepNumber < Int32(totalPulses) {
                                Rectangle()
                                    .fill(done ? PulseColors.mono : PulseColors.hair)
                                    .frame(width: 1.5)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 22)

                        // Content card — tap to expand
                        VStack(alignment: .leading, spacing: 0) {
                            // Header (always visible)
                            Button {
                                withAnimation(PulseAnimations.gentle) {
                                    if isExpanded {
                                        expandedStep = nil
                                        inlineAIQuestion = ""
                                        inlineAIResponse = ""
                                    } else {
                                        expandedStep = step.objectID
                                        inlineAIQuestion = ""
                                        inlineAIResponse = ""
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("PULSE \(String(format: "%02d", step.stepNumber))")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(PulseColors.muted)
                                        Spacer()
                                        Text(stepDateLabel(step))
                                            .font(.system(size: 10, weight: isToday ? .semibold : .regular, design: .monospaced))
                                            .foregroundColor(isToday ? PulseColors.signal : PulseColors.muted)
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(PulseColors.muted)
                                            .padding(.leading, 4)
                                    }

                                    Text(step.titleValue)
                                        .font(.system(size: 14.5, weight: .medium))
                                        .tracking(-0.14)
                                        .foregroundColor(done ? PulseColors.muted : PulseColors.ink)
                                        .strikethrough(done)
                                        .multilineTextAlignment(.leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(12)

                            // Expanded instructions section
                            if isExpanded {
                                Divider().frame(height: 0.5).background(PulseColors.hair)

                                VStack(alignment: .leading, spacing: 14) {
                                    // Instructions + Proof + Buttons — always shown,
                                    // with sensible fallbacks if AI returned empty.
                                    ExpandedPulsePanel(
                                        step: step,
                                        goal: goal,
                                        done: done,
                                        onComplete: { proofNote in
                                            step.isCompleted = true
                                            step.completedDate = Date()
                                            if !proofNote.isEmpty {
                                                step.proofNotes = proofNote
                                                step.verificationStatus = "verified"
                                            }
                                            // Persist goal progress (this path never wrote it).
                                            let total = Double(goal.totalSteps)
                                            let completed = Double(goal.completedSteps)
                                            if total > 0 { goal.currentProgress = Float((completed / total) * 100) }
                                            try? viewContext.save()
                                            let nextStep = goal.allSteps.first(where: { !$0.isCompleted && $0.objectID != step.objectID })
                                            appState.celebratePulseCompletion(
                                                pulseNumber: Int(step.stepNumber),
                                                nextPulseTitle: nextStep?.titleValue,
                                                profile: goal.userProfile,
                                                goalTitle: goal.titleValue,
                                                xpReward: Int(step.xpReward),
                                                in: viewContext
                                            )
                                            if nextStep == nil {
                                                // Whole goal finished — mark complete and show the big celebration.
                                                // Funnels through the single completion helper so every path
                                                // (Roadmap, toggleTask, workout, transformation, mentor) behaves
                                                // identically and the goal can never stay .active with all steps done.
                                                let completedID = goal.id?.uuidString ?? ""
                                                goal.markCompletedIfAllStepsDone()
                                                try? viewContext.save()
                                                // Goal is no longer active: stop its per-goal reminders and
                                                // re-evaluate the adaptive set so a finished goal stops being
                                                // referenced (and the start-a-goal nudge takes over if it was last).
                                                AdaptiveNotificationScheduler.handleGoalCompletion(goalID: completedID)
                                                let days = max(1, Calendar.current.dateComponents([.day],
                                                    from: goal.createdAt ?? Date(), to: Date()).day ?? 1)
                                                let othersDone = goal.userProfile?.goalsArray.filter {
                                                    $0.statusEnum == .completed && $0.objectID != goal.objectID
                                                }.count ?? 0
                                                appState.celebrationData = nil   // suppress per-pulse popup
                                                appState.celebrateGoalCompletion(
                                                    goalTitle: goal.titleValue,
                                                    daysTaken: days,
                                                    totalPulses: goal.totalSteps,
                                                    isFirst: othersDone == 0
                                                )
                                            } else {
                                                // Auto-open the next pulse so the user can keep going.
                                                withAnimation(.easeInOut(duration: 0.25)) {
                                                    expandedStep = nextStep?.objectID
                                                }
                                            }
                                        },
                                        onUploadProof: {
                                            // item-based binding — no race
                                            proofTask = step
                                            PulseHaptics.light()
                                        }
                                    )

                                    // Ask-AI section — free for all tiers (AI is
                                    // free for everyone; this wrapper is always true)
                                    if SubscriptionManager.shared.hasAIGeneration {
                                    Divider().frame(height: 0.5).background(PulseColors.hair)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("ASK AI ABOUT THIS PULSE")
                                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(PulseColors.signal)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                inlineQuickButton("How to start?", step: step)
                                                inlineQuickButton("What tools needed?", step: step)
                                                inlineQuickButton("Break it down", step: step)
                                                inlineQuickButton("Change instructions", step: step)
                                            }
                                        }

                                        HStack(spacing: 8) {
                                            TextField("Ask anything...", text: $inlineAIQuestion)
                                                .font(.system(size: 13))
                                                .foregroundColor(PulseColors.ink)
                                                .padding(10)
                                                .background(PulseColors.surfaceContainer)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                            Button {
                                                Task { await askInlineAI(step: step, question: inlineAIQuestion) }
                                            } label: {
                                                Image(systemName: "arrow.up.circle.fill")
                                                    .font(.system(size: 26))
                                                    .foregroundColor(inlineAIQuestion.isEmpty ? PulseColors.muted : PulseColors.signal)
                                            }
                                            .disabled(inlineAIQuestion.isEmpty || isInlineAILoading)
                                        }

                                        if isInlineAILoading {
                                            HStack(spacing: 6) {
                                                ProgressView().scaleEffect(0.7)
                                                Text("Thinking...")
                                                    .font(PulseTypography.labelSmall)
                                                    .foregroundColor(PulseColors.muted)
                                            }
                                        }

                                        if !inlineAIResponse.isEmpty {
                                            Text(inlineAIResponse)
                                                .font(.system(size: 13))
                                                .foregroundColor(PulseColors.ink)
                                                .lineSpacing(3)
                                                .padding(10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(PulseColors.signal.opacity(0.04))
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                    }
                                    } // end Ask-AI section (free for all tiers)
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isExpanded || isToday || isCurrent ? PulseColors.paper : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isExpanded ? PulseColors.signal.opacity(0.2) : (isToday || isCurrent ? Color.clear : PulseColors.hair), lineWidth: isExpanded ? 1 : 0.5)
                        )
                        .shadow(color: (isToday || isCurrent || isExpanded) ? .black.opacity(0.04) : .clear, radius: 4, y: 2)
                        .opacity(done && !isExpanded ? 0.55 : 1)
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.leading, 10)

            // Per-goal "Generate More Pulses" — extends the roadmap with N
            // fresh AI pulses that build on what's already completed.
            GenerateMorePulsesButton(goal: goal)
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 20)
                .padding(.bottom, 8)
        }
    }

    private func inlineQuickButton(_ text: String, step: DailyTask) -> some View {
        Button {
            Task { await askInlineAI(step: step, question: text) }
        } label: {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(PulseColors.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PulseColors.surfaceContainer)
                .clipShape(Capsule())
        }
        .disabled(isInlineAILoading)
    }

    private func askInlineAI(step: DailyTask, question: String) async {
        isInlineAILoading = true
        inlineAIResponse = ""
        inlineAIQuestion = question

        let prompt = """
        Goal: "\(goal.titleValue)"
        Pulse #\(step.stepNumber): "\(step.titleValue)"
        Instructions: \(step.howTo)
        Proof required: \(step.proofRequired)
        Estimated time: \(step.estimatedMinutes) minutes

        User's question about this pulse: \(question)

        Give a focused, actionable answer ONLY about this specific pulse. Be concise (2-3 paragraphs max).
        """

        do {
            let response = try await GeminiAPIService.shared.sendMessage(
                userMessage: prompt,
                systemPrompt: "You are Pulse, an AI goal coach. Answer questions about this specific task (pulse). Be direct, practical, and specific.",
                temperature: 0.7
            )
            inlineAIResponse = response
            // The "Change instructions" chip rewrites the pulse's instructions,
            // so persist the new text (the other chips are read-only Q&A).
            if question == "Change instructions",
               !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                step.howToDescription = response
                try? viewContext.save()
            }
        } catch GeminiDirectError.rateLimited {
            inlineAIResponse = "Usage limit hit"
        } catch {
            inlineAIResponse = "Couldn't get an answer right now. Try again in a moment."
        }
        isInlineAILoading = false
    }

    // MARK: - List Tab (Claude Design: simple checklist)

    private var pulseListTab: some View {
        VStack(spacing: 0) {
            ForEach(goal.allSteps, id: \.objectID) { step in
                let done = step.isCompleted
                Button {
                    toggleTask(step)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(done ? PulseColors.mono : Color.clear)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(done ? Color.clear : PulseColors.muted.opacity(0.5), lineWidth: 1.5)
                                )
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }

                        Text(step.titleValue)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(done ? PulseColors.muted : PulseColors.ink)
                            .strikethrough(done)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(stepDateLabel(step))
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundColor(PulseColors.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if step.stepNumber < Int32(totalPulses) {
                    Rectangle()
                        .fill(PulseColors.hair)
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }
            }
        }
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, 20)
    }

    // MARK: - Schedule Tab (Claude Design: grid calendar)

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(totalDays) DAYS \u{00B7} TAP TO VIEW")
                .font(PulseTypography.eyebrow)
                .eyebrowTracking()
                .foregroundColor(PulseColors.muted)
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 20)

            let columns = 10
            let cells = buildScheduleCells()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(0..<cells.count, id: \.self) { i in
                    let cell = cells[i]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cell.color)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Group {
                                if let pulse = cell.pulseNumber {
                                    Text("\(pulse)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(cell.textColor)
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(cell.isToday ? Color.clear : (cell.hasPulse && !cell.isPast ? PulseColors.hair : Color.clear), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let id = cell.objectID else { return }
                            PulseHaptics.selection()
                            withAnimation(PulseAnimations.gentle) {
                                expandedStep = id
                                inlineAIQuestion = ""
                                inlineAIResponse = ""
                                selectedTab = 0
                            }
                        }
                }
            }
            .padding(.horizontal, PulseSpacing.screenEdge)

            // Legend
            HStack(spacing: 14) {
                legendItem(color: PulseColors.mono, label: "Done")
                legendItem(color: PulseColors.signal, label: "Today")
                legendItem(color: PulseColors.paper, label: "Upcoming", bordered: true)
            }
            .font(.system(size: 11.5))
            .foregroundColor(PulseColors.muted)
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.top, 16)
        }
    }

    // MARK: - Helpers

    private func isStepToday(_ step: DailyTask) -> Bool {
        guard let date = step.scheduledDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private func stepDateLabel(_ step: DailyTask) -> String {
        guard let date = step.scheduledDate else { return "" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func toggleTask(_ task: DailyTask) {
        task.isCompleted.toggle()
        let profile = UserProfile.fetchOrCreate(in: viewContext)
        if task.isCompleted {
            task.completedDate = Date()
            PulseHaptics.success()
        } else {
            task.completedDate = nil
        }
        // Update goal progress (mirrors markStepComplete / the timeline path).
        let total = Double(goal.totalSteps)
        let completed = Double(goal.completedSteps)
        if total > 0 { goal.currentProgress = Float((completed / total) * 100) }
        // Finish the goal + stop its reminders if this completed the last step.
        let goalID = goal.id?.uuidString ?? ""
        let justCompleted = task.isCompleted && goal.markCompletedIfAllStepsDone()
        try? viewContext.save()
        if justCompleted {
            AdaptiveNotificationScheduler.handleGoalCompletion(goalID: goalID)
        }
        // XP/level/streak/widget go through the single canonical path. On
        // complete this also shows the celebration overlay; on un-complete the
        // XP is returned and the level re-derives. When the last step is done,
        // suppress the per-pulse popup and show the goal-completion screen instead
        // (mirrors the ExpandedPulsePanel / Roadmap path so all 3 paths behave the same).
        if task.isCompleted {
            if justCompleted {
                appState.celebrationData = nil
                let days = max(1, Calendar.current.dateComponents([.day],
                    from: goal.createdAt ?? Date(), to: Date()).day ?? 1)
                let othersDone = goal.userProfile?.goalsArray.filter {
                    $0.statusEnum == .completed && $0.objectID != goal.objectID
                }.count ?? 0
                appState.celebrateGoalCompletion(
                    goalTitle: goal.titleValue,
                    daysTaken: days,
                    totalPulses: goal.totalSteps,
                    isFirst: othersDone == 0
                )
            } else {
                appState.celebratePulseCompletion(
                    pulseNumber: Int(task.stepNumber),
                    nextPulseTitle: nil,
                    profile: profile,
                    goalTitle: goal.title,
                    xpReward: Int(task.xpReward),
                    in: viewContext
                )
            }
        } else {
            profile.unregisterCompletion(xp: Int(task.xpReward), in: viewContext)
        }
    }

    private func legendItem(color: Color, label: String, bordered: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    bordered ? RoundedRectangle(cornerRadius: 2).stroke(PulseColors.hair, lineWidth: 1) : nil
                )
            Text(label)
        }
    }

    private struct ScheduleCell {
        let color: Color
        let textColor: Color
        let pulseNumber: Int?
        let isPast: Bool
        let isToday: Bool
        let hasPulse: Bool
        let objectID: NSManagedObjectID?
    }

    private func buildScheduleCells() -> [ScheduleCell] {
        let steps = goal.allSteps
        var cells: [ScheduleCell] = []

        for day in 0..<totalDays {
            let date = Calendar.current.date(byAdding: .day, value: day, to: goal.createdDate ?? Date()) ?? Date()
            let isPast = date < Calendar.current.startOfDay(for: Date())
            let isToday = Calendar.current.isDateInToday(date)

            // Find pulse scheduled for this day
            let pulse = steps.first { step in
                guard let sched = step.scheduledDate else { return false }
                return Calendar.current.isDate(sched, inSameDayAs: date)
            }

            if let pulse = pulse {
                let done = pulse.isCompleted
                cells.append(ScheduleCell(
                    color: done ? PulseColors.mono : (isToday ? PulseColors.signal : PulseColors.paper),
                    textColor: done || isToday ? .white : PulseColors.ink,
                    pulseNumber: Int(pulse.stepNumber),
                    isPast: isPast,
                    isToday: isToday,
                    hasPulse: true,
                    objectID: pulse.objectID
                ))
            } else {
                cells.append(ScheduleCell(
                    color: isPast ? PulseColors.ink.opacity(0.08) : PulseColors.ink.opacity(0.04),
                    textColor: .clear,
                    pulseNumber: nil,
                    isPast: isPast,
                    isToday: isToday,
                    hasPulse: false,
                    objectID: nil
                ))
            }
        }

        return cells
    }
}

// MARK: - Goal Extensions for Detail View

extension Goal {
    var createdDate: Date? {
        createdAt
    }

    var daysElapsed: Int {
        guard let deadline = deadline else { return 0 }
        let totalDays = max(1, Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0) + daysRemaining
        return max(0, totalDays - daysRemaining)
    }

    var startDateLabel: String {
        if let created = createdDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: created).uppercased()
        }
        return "START"
    }

    var deadlineLabel: String {
        guard let deadline = deadline else { return "DEADLINE" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: deadline).uppercased()
    }

}

// MARK: - Rename Goal Sheet

private struct RenameGoalSheet: View {
    @ObservedObject var goal: Goal
    @Binding var text: String
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Rename Goal")
                    .font(PulseTypography.titleLarge)
                    .foregroundColor(PulseColors.textPrimary)

                TextField("Goal name", text: $text)
                    .font(.system(size: 17))
                    .foregroundColor(PulseColors.textPrimary)
                    .padding(16)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Save") {
                    goal.title = text
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(M3FilledButton())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(PulseSpacing.screenEdge)
            .pulseScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Add Step Sheet (manual self-authored pulse — free plan friendly)

struct AddStepSheet: View {
    @ObservedObject var goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var title: String = ""
    @State private var howTo: String = ""
    @State private var proof: String = ""

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Write your own step. We'll check in on it daily.")
                        .font(.system(size: 13))
                        .foregroundColor(PulseColors.muted)

                    field("STEP") {
                        TextField("e.g. Run for 20 minutes", text: $title)
                            .font(.system(size: 16, weight: .medium))
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    field("HOW (OPTIONAL)") {
                        TextField("Any detail on how to do it", text: $howTo, axis: .vertical)
                            .font(.system(size: 14)).lineLimit(2...5)
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    field("PROOF (OPTIONAL)") {
                        TextField("What shows it's done", text: $proof)
                            .font(.system(size: 14))
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button { save() } label: {
                        Text("Add step")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(canSave ? PulseColors.signal : PulseColors.muted.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!canSave)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.vertical, 16)
            }
            .pulseScreen()
            .dismissKeyboardOnTap()
            .navigationTitle("Add a Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(PulseColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4).foregroundColor(PulseColors.muted)
            content()
        }
    }

    private func save() {
        let existing = (goal.dailyTasks as? Set<DailyTask>) ?? []
        let nextStep = (existing.map { Int($0.stepNumber) }.max() ?? 0) + 1
        let task = DailyTask(context: viewContext)
        task.id = UUID()
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.howToDescription = howTo.trimmingCharacters(in: .whitespacesAndNewlines)
        task.taskDescription = task.howToDescription
        task.proofDescription = proof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Describe what you did." : proof
        task.proofType = "text"
        task.stepNumber = Int16(nextStep)
        task.sortOrder = Int16(existing.count)
        task.estimatedMinutes = 15
        task.xpReward = 10
        task.verificationStatus = "pending"
        task.isCompleted = false
        task.scheduledDate = Date()
        task.goal = goal
        try? viewContext.save()
        PulseHaptics.success()
        Task { try? await FirestoreSyncService.shared.syncGoal(goal) }
        dismiss()
    }
}
