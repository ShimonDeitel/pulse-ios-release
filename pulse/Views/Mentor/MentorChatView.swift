import SwiftUI
import CoreData

struct MentorChatView: View {
    /// When set, this is a goal's PRIVATE chat room: the goal is fixed (no goal
    /// picker), and the conversation is persisted per-goal so it's there next
    /// time. When nil (the global Chat tab) the user picks which goal's room
    /// to open via the chips.
    var fixedGoal: Goal? = nil
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel = MentorChatViewModel()
    @State private var showPaywall = false
    /// When false (the default), messages older than 24h are cleared on load.
    /// The clock button in the toolbar flips this on/off.
    @AppStorage("chatAutoExpireDisabled") private var autoExpireDisabled = false
    #if DEBUG
    // DEBUG only: lets the owner paste a test AI key so the agent can run without
    // the production proxy. Compiled out of Release/TestFlight bytes entirely.
    @State private var showAIKeyEntry = false
    @State private var aiKeyInput = ""
    @State private var aiConfigured = false
    #endif
    @FocusState private var isInputFocused: Bool
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)],
        predicate: NSPredicate(format: "status == %@", GoalStatus.active.rawValue),
        animation: .default
    )
    private var goals: FetchedResults<Goal>

    var body: some View {
        if SubscriptionManager.shared.hasAIGeneration {
            #if DEBUG
            chatView
                .onAppear { aiConfigured = DeepSeekClient.shared.isConfigured }
                .alert("Connect AI (testing)", isPresented: $showAIKeyEntry) {
                    TextField("DeepSeek API key", text: $aiKeyInput)
                    Button("Save") {
                        let k = aiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !k.isEmpty { _ = KeychainManager.shared.save(key: .deepSeekAPIKey, value: k) }
                        aiKeyInput = ""
                        aiConfigured = DeepSeekClient.shared.isConfigured
                        PulseHaptics.success()
                    }
                    Button("Cancel", role: .cancel) { aiKeyInput = "" }
                } message: {
                    Text("Paste a DeepSeek API key to test the AI locally (DEBUG only). For production, set PULSE_PROXY_BASE_URL instead.")
                }
            #else
            chatView
            #endif
        } else {
            LockedFeatureView(
                title: "AI Chat",
                message: "Chat with a personal AI that knows your goals, streak, and progress, and pushes you in your chosen style. Free for everyone — Pro adds Primary Access (priority) and unlimited goals.",
                icon: "bubble.left.and.text.bubble.right.fill"
            )
            .navigationTitle("Chat".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            #if DEBUG
            // DEBUG only: surface AI-not-connected so the owner can plug in a test
            // key. In Release/TestFlight the proxy is configured and this whole
            // block is compiled out.
            if !aiConfigured {
                Button { showAIKeyEntry = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text("AI not connected — tap to add a test key")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PulseColors.signal)
                }
                .buttonStyle(.plain)
            }
            #endif

            // Goal picker — only in the global Chat tab. In a goal's private
            // room the goal is fixed, so we hide the picker entirely.
            if fixedGoal == nil && !goals.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PulseSpacing.sm) {
                        ForEach(goals) { goal in
                            Button {
                                viewModel.switchGoal(goal, context: viewContext)
                            } label: {
                                Text(goal.titleValue)
                                    .font(PulseTypography.labelMedium)
                                    .foregroundColor(viewModel.selectedGoal?.id == goal.id ? PulseColors.textPrimary : PulseColors.textTertiary)
                                    .padding(.horizontal, PulseSpacing.md)
                                    .padding(.vertical, PulseSpacing.sm)
                                    .background(viewModel.selectedGoal?.id == goal.id ? PulseColors.surfaceContainer : Color.clear)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, PulseSpacing.screenEdge)
                    .padding(.vertical, PulseSpacing.sm)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PulseSpacing.sm) {
                    ForEach(MentorPersonality.allCases) { personality in
                        Button {
                            viewModel.selectPersonality(personality, context: viewContext)
                        } label: {
                            HStack(spacing: PulseSpacing.xs) {
                                Image(systemName: personality.icon)
                                    .font(.system(size: 11))
                                Text(personality.localizedDisplayName)
                                    .font(PulseTypography.labelSmall)
                            }
                            .foregroundColor(viewModel.selectedPersonality == personality ? PulseColors.signal : PulseColors.textTertiary)
                            .padding(.horizontal, PulseSpacing.md)
                            .padding(.vertical, PulseSpacing.xs + 2)
                            .background(viewModel.selectedPersonality == personality ? PulseColors.signal.opacity(0.1) : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(viewModel.selectedPersonality == personality ? PulseColors.signal.opacity(0.2) : PulseColors.outlineVariant, lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, PulseSpacing.sm)
            }

            Rectangle()
                .fill(PulseColors.outlineVariant)
                .frame(height: 0.5)

            // Chat messages — tap to dismiss keyboard
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: PulseSpacing.md) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isTyping {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, PulseSpacing.screenEdge)
                            .id("typing")
                        }
                    }
                    .padding(.vertical, PulseSpacing.lg)
                }
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation(PulseAnimations.standard) {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
            }

            // Input bar
            HStack(spacing: PulseSpacing.sm) {
                TextField("Message...".localized, text: $viewModel.inputText, axis: .vertical)
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textPrimary)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .padding(.horizontal, PulseSpacing.md)
                    .padding(.vertical, PulseSpacing.md - 2)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                            .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                    )
                    .submitLabel(.send)
                    .onSubmit {
                        if !viewModel.inputText.isEmpty && !viewModel.isTyping {
                            Task { await viewModel.sendMessage(context: viewContext) }
                        }
                    }

                Button {
                    isInputFocused = false
                    Task {
                        await viewModel.sendMessage(context: viewContext)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(viewModel.inputText.isEmpty ? PulseColors.textTertiary : PulseColors.signal)
                        // Guarantee a comfortable, reliably-tappable hit target even
                        // when the glyph itself is small.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Send message")
                .disabled(viewModel.inputText.isEmpty || viewModel.isTyping)
            }
            .padding(.horizontal, PulseSpacing.lg)
            .padding(.vertical, PulseSpacing.md)
            .background(PulseColors.surface)
        }
        .pulseScreen()
        .navigationTitle(fixedGoal?.titleValue ?? "Chat".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    autoExpireDisabled.toggle()
                    PulseHaptics.light()
                    // Apply immediately — turning it back on sweeps anything >24h now.
                    if let g = viewModel.selectedGoal { viewModel.loadHistory(for: g) }
                } label: {
                    Image(systemName: autoExpireDisabled ? "clock.badge.xmark" : "clock.arrow.circlepath")
                        .foregroundColor(autoExpireDisabled ? PulseColors.textTertiary : PulseColors.signal)
                }
                .accessibilityLabel(autoExpireDisabled
                    ? "Messages are kept. Tap to auto-clear after 24 hours."
                    : "Messages auto-clear after 24 hours. Tap to keep them.")
            }
        }
        .onAppear {
            // Restore the user's chosen mentor voice from their profile BEFORE the
            // opening greeting is generated, so the greeting (and notifications)
            // use the saved personality instead of always defaulting to Coach.
            viewModel.loadPersistedPersonality(context: viewContext)
            if viewModel.selectedGoal == nil {
                viewModel.selectedGoal = fixedGoal ?? goals.first
            }
            // Load this goal's saved chat history (its private room) exactly once.
            if !viewModel.didLoadHistory, let g = viewModel.selectedGoal {
                viewModel.loadHistory(for: g)
            }
            // Proactive greeting: only if this room has no prior history.
            if viewModel.messages.isEmpty, viewModel.selectedGoal != nil {
                Task { await viewModel.sendProactiveGreeting(context: viewContext) }
            }
        }
        .sheet(isPresented: $viewModel.showLimitReachedModal) {
            LimitReachedModal(
                currentTier: viewModel.limitReachedFromTier,
                suggestedUpgrade: viewModel.limitSuggestedUpgrade,
                onUpgrade: { _ in
                    // Route to the real StoreKit paywall — purchasing is the only
                    // way to unlock Pro. Swap sheets after this one dismisses.
                    viewModel.showLimitReachedModal = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPaywall = true
                    }
                },
                onClose: {
                    viewModel.showLimitReachedModal = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) {
            UpgradeView()
        }
    }
}

@Observable
class MentorChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isTyping = false
    var selectedGoal: Goal?
    var selectedPersonality: MentorPersonality = .coach

    // Limit-reached modal state
    var showLimitReachedModal: Bool = false
    var limitReachedFromTier: SubscriptionTier = .free
    var limitSuggestedUpgrade: SubscriptionTier? = nil

    /// Seed the picker from the persisted profile so the chosen mentor voice
    /// survives relaunch. Must run BEFORE the opening greeting is generated.
    func loadPersistedPersonality(context: NSManagedObjectContext) {
        selectedPersonality = UserProfile.fetchOrCreate(in: context).mentorPersonalityEnum
    }

    /// Persist the user's pick to the profile so it sticks across relaunches and
    /// the notification scheduler (which reads `profile.mentorPersonality`) uses
    /// the chosen voice rather than always defaulting to Coach.
    func selectPersonality(_ personality: MentorPersonality, context: NSManagedObjectContext) {
        selectedPersonality = personality
        let profile = UserProfile.fetchOrCreate(in: context)
        profile.mentorPersonalityEnum = personality
        try? context.save()
    }

    // MARK: - Per-goal persistence (each goal has its own private chat room)

    /// True once a goal's stored thread has been loaded into `messages`, so we
    /// don't reload (and clobber the live conversation) on every onAppear.
    var didLoadHistory = false

    /// Load a goal's saved chat history (its private room) into `messages`.
    func loadHistory(for goal: Goal) {
        // 24h auto-expire: when enabled (the default; toggled off via the clock
        // button), permanently drop messages older than 24 hours before loading.
        if !UserDefaults.standard.bool(forKey: "chatAutoExpireDisabled") {
            let cutoff = Date().addingTimeInterval(-86_400)   // 24h
            let stale = goal.mentorMessagesArray.filter { ($0.timestamp ?? .distantPast) < cutoff }
            if !stale.isEmpty, let ctx = goal.managedObjectContext {
                stale.forEach(ctx.delete)
                try? ctx.save()
            }
        }
        // mentorMessagesArray is already sorted by timestamp, so array order
        // preserves chronology (ChatMessage's id/timestamp are auto-assigned).
        messages = goal.mentorMessagesArray.map { m in
            ChatMessage(content: m.contentValue, isFromUser: m.isFromUser)
        }
        didLoadHistory = true
    }

    /// Split an AI reply into the "|||"-separated short messages it was asked to
    /// produce (falling back to paragraph splits), so they pop in one-by-one like
    /// texts. Capped so we never spam a wall of tiny bubbles.
    private func splitBubbles(_ text: String) -> [String] {
        let source = text.contains("|||") ? text.components(separatedBy: "|||")
                                          : text.components(separatedBy: "\n\n")
        let parts = source
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array((parts.isEmpty ? [whole] : parts).prefix(6))
    }

    /// Append each bubble with a brief "typing" pause between, so a reply lands
    /// message-after-message like a friend texting. Persists every bubble.
    private func appendBubbles(_ text: String, context: NSManagedObjectContext) async {
        for (i, bubble) in splitBubbles(text).enumerated() {
            if i > 0 {
                isTyping = true
                let pause = min(1.3, max(0.45, Double(bubble.count) / 110.0))
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                isTyping = false
            }
            messages.append(ChatMessage(content: bubble, isFromUser: false))
            persist(bubble, isFromUser: false, context: context)
        }
    }

    /// Switch to another goal's room (global Chat tab only): load its saved
    /// thread, and open with a greeting only if that room is empty.
    func switchGoal(_ goal: Goal, context: NSManagedObjectContext) {
        guard goal.objectID != selectedGoal?.objectID else { return }
        selectedGoal = goal
        loadHistory(for: goal)
        if messages.isEmpty {
            Task { await sendProactiveGreeting(context: context) }
        }
    }

    /// Append one message to the selected goal's persistent thread (Core Data,
    /// mirrored to the user's private iCloud). No-op if no goal is selected.
    private func persist(_ content: String, isFromUser: Bool, context: NSManagedObjectContext) {
        guard let goal = selectedGoal else { return }
        let m = MentorMessage(context: context)
        m.id = UUID()
        m.content = content
        m.isFromUser = isFromUser
        m.timestamp = Date()
        m.messageType = "chat"
        m.personality = selectedPersonality.rawValue
        m.goal = goal
        try? context.save()
    }

    /// Mentor opens the conversation first. Pulls real goal data and the
    /// personality's voice. Runs once per chat session.
    func sendProactiveGreeting(context: NSManagedObjectContext) async {
        guard messages.isEmpty, let goal = selectedGoal else { return }
        isTyping = true

        let completedCount = goal.completedSteps
        let totalCount = goal.totalSteps
        let pct = totalCount > 0 ? Int(Double(completedCount) / Double(totalCount) * 100) : 0
        let userName = goal.userProfile?.displayName ?? "there"

        let goalContext = """
        USER'S CURRENT GOAL: "\(goal.titleValue)"
        Category: \(goal.categoryEnum.displayName)
        Progress: \(pct)% (\(completedCount)/\(totalCount) pulses completed)
        Days remaining: \(goal.daysRemaining)
        User's first name: \(userName)
        """

        let systemPrompt = selectedPersonality.systemPrompt + "\n\n" + goalContext + """


        OPEN THE CONVERSATION FIRST. The user just opened the chat — they have not
        said anything yet. Greet them by name, reference their actual progress on
        their goal, and ask ONE specific question that moves them forward today.
        Maximum 2 short paragraphs. Match your personality exactly.
        """

        do {
            let response = try await GeminiAPIService.shared.sendMessage(
                userMessage: "(User just opened the chat. Say hi first.)",
                systemPrompt: systemPrompt,
                temperature: 0.85
            )
            isTyping = false
            await appendBubbles(response, context: context)
        } catch {
            // Silent fail on proactive greeting — user can still type to start
            isTyping = false
        }
    }

    func sendMessage(context: NSManagedObjectContext) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Moderation gate (App Review 1.2): reject egregiously objectionable
        // input before it ever reaches the AI, with an in-line system reply
        // instead of forwarding it. The display-time mask still covers anything
        // that slips through on either side.
        if ContentFilter.containsObjectionable(text) {
            inputText = ""
            messages.append(ChatMessage(content: text, isFromUser: true))
            messages.append(ChatMessage(
                content: "Let's keep this focused on your goals. I can't help with that.",
                isFromUser: false))
            PulseHaptics.warning()
            return
        }

        let userMsg = ChatMessage(content: text, isFromUser: true)
        messages.append(userMsg)
        persist(text, isFromUser: true, context: context)
        inputText = ""
        isTyping = true

        // Build rich context about the user's goal
        var goalContext = ""
        if let goal = selectedGoal {
            let completedCount = goal.completedSteps
            let totalCount = goal.totalSteps
            let pct = totalCount > 0 ? Int(Double(completedCount) / Double(totalCount) * 100) : 0

            goalContext = """
            USER'S CURRENT GOAL: "\(goal.titleValue)"
            Category: \(goal.categoryEnum.displayName)
            Progress: \(pct)% (\(completedCount)/\(totalCount) pulses completed)
            Days remaining: \(goal.daysRemaining)
            Deadline: \(goal.deadline.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "None set")
            Skill level: \(goal.skillLevel ?? "Not specified")
            Motivation: \(goal.motivationLevel)/10
            Obstacles: \(goal.obstacles ?? "None specified")
            """

            // Add today's tasks context
            let todayTasks = goal.todaysTasks
            if !todayTasks.isEmpty {
                let doneTasks = todayTasks.filter { $0.isCompleted }
                goalContext += "\nToday's pulses: \(doneTasks.count)/\(todayTasks.count) done"
                if let nextTask = todayTasks.first(where: { !$0.isCompleted }) {
                    goalContext += "\nNext pulse: \"\(nextTask.titleValue)\""
                }
            }
        }

        let systemPrompt = selectedPersonality.systemPrompt + "\n\n" + goalContext

        let history = messages.dropLast().suffix(20).map { msg in
            (role: msg.isFromUser ? "user" : "assistant", content: msg.content)
        }

        do {
            // When DeepSeek tool-calling is live, route through MentorAgent so the
            // chat can actually OPERATE the app — add/edit/delete pulses, rebuild
            // the plan, reshape the goal, and search the live web. Without a
            // DeepSeek key we fall back to a plain one-shot chat turn.
            // Throws AIRouterError.limitReached if a paid user hit their budget.
            let response: String
            if AIRouter.shared.toolCallingAvailable {
                let outcome = try await MentorAgent.shared.run(
                    userMessage: text,
                    personalityPrompt: selectedPersonality.systemPrompt,
                    history: Array(history),
                    goalObjectID: selectedGoal?.objectID
                )
                response = outcome.reply
            } else {
                response = try await AIRouter.shared.sendMessage(
                    userMessage: text,
                    systemPrompt: systemPrompt,
                    conversationHistory: Array(history),
                    temperature: 0.8
                )
            }
            isTyping = false
            // Land the reply as several short texts, one after another, and
            // persist each so both sides of the thread survive a relaunch.
            await appendBubbles(response, context: context)
        } catch let aiError as AIRouterError {
            // Budget exhausted → ask the UI layer to show the upgrade modal.
            if case .limitReached(let tier, let suggested) = aiError {
                limitReachedFromTier = tier
                limitSuggestedUpgrade = suggested
                showLimitReachedModal = true
            }
        } catch {
            let friendly: String
            if let urlError = error as? URLError,
               [.networkConnectionLost, .timedOut, .notConnectedToInternet].contains(urlError.code) {
                friendly = "Hmm — the connection dropped. Tap send again and I'll pick up where we left off."
            } else if let g = error as? GeminiDirectError {
                switch g {
                case .rateLimited:
                    friendly = "Easy there, that was fast. Give it a few seconds and try again."
                case .noAPIKey:
                    // The real cause when no proxy URL + no key is configured.
                    #if DEBUG
                    friendly = "Pulse AI isn't connected. Add a test key with “Connect AI” at the top of this screen, or set PULSE_PROXY_BASE_URL."
                    #else
                    friendly = "Pulse AI is temporarily unavailable. Please try again soon."
                    #endif
                default:
                    friendly = "Pulse AI hit a snag. Please try again in a moment."
                }
            } else {
                friendly = "Pulse AI hit a snag. Please try again in a moment."
            }
            #if DEBUG
            messages.append(ChatMessage(content: friendly + "\n\n[debug] \(error)", isFromUser: false))
            #else
            messages.append(ChatMessage(content: friendly, isFromUser: false))
            #endif
        }

        isTyping = false
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isFromUser: Bool
    let timestamp = Date()
}

struct MessageBubble: View {
    let message: ChatMessage

    /// Render the masked message as lightweight markdown so the coach's meal
    /// plans / workouts show bold section labels and clean line breaks (not
    /// literal ** / - markup). Inline-only + preserved whitespace keeps newlines
    /// and bullet dashes intact; falls back to plain text if parsing fails.
    private var rendered: Text {
        let masked = ContentFilter.masked(message.content)
        if let attributed = try? AttributedString(
            markdown: masked,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(masked)
    }

    var body: some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 64) }

            // Always-on 13+ content filter (masked inside `rendered`), then shown
            // as lightweight markdown so plans/workouts format cleanly.
            rendered
                .font(PulseTypography.bodyMedium)
                .multilineTextAlignment(.leading)
                .foregroundColor(message.isFromUser ? PulseColors.onPrimary : PulseColors.textPrimary)
                .padding(.horizontal, PulseSpacing.lg)
                .padding(.vertical, PulseSpacing.md)
                .background(message.isFromUser ? PulseColors.mono : PulseColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: M3Shapes.extraLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: M3Shapes.extraLarge, style: .continuous)
                        .stroke(message.isFromUser ? Color.clear : PulseColors.outlineVariant, lineWidth: 0.5)
                )
                // App Review Guideline 1.2: any AI-/user-generated content surface
                // must let users flag objectionable output. Long-press an AI reply
                // to Report it (or Copy any message).
                .contextMenu { messageActions }

            if !message.isFromUser { Spacer(minLength: 64) }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    @ViewBuilder private var messageActions: some View {
        if !message.isFromUser {
            Button(role: .destructive, action: reportMessage) {
                Label("Report", systemImage: "flag")
            }
        }
        Button(action: copyMessage) {
            Label("Copy", systemImage: "doc.on.doc")
        }
    }

    private func copyMessage() {
        UIPasteboard.general.string = message.content
        PulseHaptics.light()
    }

    /// Flag an objectionable AI reply to support. Opens a prefilled report email
    /// (the content moderation channel) and confirms with a haptic.
    private func reportMessage() {
        PulseHaptics.success()
        let subject = "Report objectionable AI content"
        let body = "I'm reporting this AI response as objectionable:\n\n\(message.content)"
        let q = "subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:meir56885@gmail.com?\(q)") {
            UIApplication.shared.open(url)
        }
    }
}

struct TypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: PulseSpacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(PulseColors.textTertiary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, PulseSpacing.lg)
        .padding(.vertical, PulseSpacing.md)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: M3Shapes.extraLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: M3Shapes.extraLarge, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )
        .onAppear { animate = true }
    }
}
