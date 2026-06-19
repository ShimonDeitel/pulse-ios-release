import SwiftUI
import CoreData

struct FocusSessionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDuration: Int = 25
    @State private var isRunning = false
    @State private var timeRemaining: Int = 25 * 60
    @State private var timer: Timer?
    @State private var startTime: Date?
    @State private var isPaused = false
    // Custom-duration support: the user can dial any length from 1–180 min
    // instead of being limited to the preset chips.
    @State private var isCustomSelected = false
    @State private var customMinutes = 30
    // Confirmation before abandoning a running session (the exit is always
    // available now, so we guard it to avoid losing focus progress by accident).
    @State private var showExitConfirm = false

    private let customRange = 1...180

    /// Optional caller-supplied goal. When nil (e.g. launched from the
    /// dashboard Focus quick action), we resolve the first active goal so the
    /// session still records time + XP against something real.
    var goal: Goal? = nil

    let durations = [15, 25, 45, 60, 90]

    /// The goal this session counts toward: the one passed in, or the
    /// soonest-deadline active goal if none was supplied.
    private var resolvedGoal: Goal? {
        if let goal = goal { return goal }
        let req: NSFetchRequest<Goal> = Goal.fetchRequest()
        req.predicate = NSPredicate(format: "status == %@", GoalStatus.active.rawValue)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Goal.deadline, ascending: true)]
        req.fetchLimit = 1
        return try? viewContext.fetch(req).first
    }

    var body: some View {
        VStack(spacing: PulseSpacing.xxxl) {
            if !isRunning {
                preSessionView
            } else {
                timerView
            }
        }
        .pulseScreen()
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Always-available escape hatch — whether or not a session is
            // running, the user can leave. When a session is in progress we
            // confirm first so focus time is never lost by an accidental tap.
            ToolbarItem(placement: .topBarLeading) {
                Button { attemptExit() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(PulseColors.textSecondary)
                }
                .accessibilityLabel("Close")
            }
        }
        .confirmationDialog("End focus session?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { endSession(completed: false) }
            Button("Keep Focusing", role: .cancel) { }
        } message: {
            Text("Your focus time so far won’t earn XP unless the full session completes.")
        }
        .onDisappear { timer?.invalidate() }
    }

    /// Leaving the screen: if a session is running, confirm before abandoning it;
    /// otherwise just dismiss.
    private func attemptExit() {
        if isRunning {
            showExitConfirm = true
        } else {
            dismiss()
        }
    }

    private var preSessionView: some View {
        VStack(spacing: PulseSpacing.xxxl) {
            Spacer()

            VStack(spacing: PulseSpacing.sm) {
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(PulseColors.signal)

                Text("Focus Timer".localized)
                    .font(PulseTypography.headlineLarge)
                    .foregroundColor(PulseColors.ink)
                    .headlineTracking()
            }

            if let goal = resolvedGoal {
                Text(goal.titleValue)
                    .font(PulseTypography.bodyLarge)
                    .foregroundColor(PulseColors.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PulseSpacing.md) {
                    ForEach(durations, id: \.self) { duration in
                        let isOn = !isCustomSelected && selectedDuration == duration
                        Button {
                            isCustomSelected = false
                            selectedDuration = duration
                            timeRemaining = duration * 60
                            PulseHaptics.light()
                        } label: {
                            Text("\(duration)m")
                                .font(PulseTypography.monoCaption)
                                .foregroundColor(isOn ? PulseColors.onPrimary : PulseColors.textSecondary)
                                .frame(width: 52, height: 52)
                                .background(isOn ? PulseColors.primary : PulseColors.surfaceContainer)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(isOn ? Color.clear : PulseColors.outlineVariant, lineWidth: 0.5)
                                )
                        }
                    }

                    // Custom — opens a 1–180 min wheel so any focus length works.
                    Button {
                        isCustomSelected = true
                        selectedDuration = customMinutes
                        timeRemaining = customMinutes * 60
                        PulseHaptics.light()
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .medium))
                            Text("Custom")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(isCustomSelected ? PulseColors.onPrimary : PulseColors.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(isCustomSelected ? PulseColors.primary : PulseColors.surfaceContainer)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isCustomSelected ? Color.clear : PulseColors.outlineVariant, lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, PulseSpacing.section)
            }

            if isCustomSelected {
                VStack(spacing: PulseSpacing.xs) {
                    Text("\(customMinutes) min")
                        .font(PulseTypography.monoCaption)
                        .foregroundColor(PulseColors.textPrimary)
                    Picker("Minutes", selection: $customMinutes) {
                        ForEach(customRange, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .onChange(of: customMinutes) {
                        selectedDuration = customMinutes
                        timeRemaining = customMinutes * 60
                    }
                }
                .padding(.horizontal, PulseSpacing.section)
            }

            Button("Start Focus") {
                startSession()
            }
            .buttonStyle(M3FilledButton())
            .padding(.horizontal, PulseSpacing.section)

            Spacer()
        }
    }

    private var timerView: some View {
        VStack(spacing: PulseSpacing.section) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(PulseColors.surfaceContainer, lineWidth: 6)
                    .frame(width: 240, height: 240)

                Circle()
                    .trim(from: 0, to: Double(timeRemaining) / Double(selectedDuration * 60))
                    .stroke(timerColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 240, height: 240)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)

                VStack(spacing: PulseSpacing.xs) {
                    Text(timeString)
                        .font(PulseTypography.monoLarge)
                        .foregroundColor(PulseColors.textPrimary)
                    Text(isPaused ? "Paused" : "Focusing")
                        .font(PulseTypography.labelMedium)
                        .foregroundColor(isPaused ? PulseColors.warning : PulseColors.textTertiary)
                }
            }

            HStack(spacing: PulseSpacing.xxl) {
                Button {
                    attemptExit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(PulseColors.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(Circle())
                }

                Button {
                    togglePause()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22))
                        .foregroundColor(PulseColors.onPrimary)
                        .frame(width: 68, height: 68)
                        .background(PulseColors.primary)
                        .clipShape(Circle())
                }
            }

            Spacer()
        }
    }

    private var timerColor: Color {
        let fraction = Double(timeRemaining) / Double(selectedDuration * 60)
        if fraction > 0.5 { return PulseColors.primary }
        if fraction > 0.2 { return PulseColors.warning }
        return PulseColors.danger
    }

    private var timeString: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startSession() {
        isRunning = true
        startTime = Date()
        timeRemaining = selectedDuration * 60
        startTimer()
        PulseHaptics.medium()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                endSession(completed: true)
            }
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
        } else {
            startTimer()
        }
        PulseHaptics.light()
    }

    private func endSession(completed: Bool) {
        timer?.invalidate()

        if let goal = resolvedGoal, let start = startTime {
            let session = FocusSession(context: viewContext)
            session.id = UUID()
            session.startTime = start
            session.endTime = Date()
            session.plannedDurationMinutes = Int16(selectedDuration)
            session.actualDurationMinutes = Int16(Int(Date().timeIntervalSince(start)) / 60)
            session.wasCompleted = completed
            session.xpEarned = completed ? Int32(selectedDuration / 5 * 10) : 0
            session.goal = goal

            if completed {
                // Canonical completion path: award the focus XP through
                // registerCompletion so the level is re-derived, the daily
                // streak advances, and the home-screen widget refreshes — never
                // mutate totalXP directly. (This save also persists the session.)
                let profile = UserProfile.fetchOrCreate(in: viewContext)
                profile.registerCompletion(xp: Int(session.xpEarned), in: viewContext)
            } else {
                try? viewContext.save()
            }
        }

        if completed {
            PulseHaptics.success()
        }
        dismiss()
    }
}
