import SwiftUI
import AVFoundation

/// Full-screen "Live Mode" for a single exercise.
///
/// Flow:
///   1. Open → request camera permission, start selfie feed
///   2. Show "Place phone, get in position" with motion-confidence meter
///   3. Once pose detection sees the user moving (confidence > 0.6),
///      auto-start the work timer
///   4. Timer ticks down with big readout overlay
///   5. On finish: TTS rings "Rest", switches to rest timer
///   6. After rest: TTS rings "Go", restarts work timer for next set
///   7. After last set: TTS rings "Done", dismiss
struct LiveWorkoutView: View {
    let exercise: WorkoutExercise
    /// Called when the exercise auto-completes (all sets done). Parent uses
    /// this to mark the exercise off in the workout sheet's completedSet —
    /// enabling auto-finish of the whole workout when the last one wraps up.
    var onComplete: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var pose = PoseDetectionService()
    @State private var phase: Phase = .waiting
    @State private var currentSet: Int = 1
    @State private var secondsRemaining: Int = 0
    @State private var timerCancellable: Timer?
    @State private var speech = AVSpeechSynthesizer()

    @State private var lastEncouragementAt: Int = -1
    /// Pauses the countdown (used for the rest timer's Pause/Resume button).
    @State private var timerPaused = false

    /// When true, the spoken coach voice (countdown numbers + cues) is silenced.
    /// The non-verbal tick/bell sound effects still play. Persisted so the
    /// choice sticks across workouts.
    @State private var voiceMuted: Bool = UserDefaults.standard.bool(forKey: "pulse_live_voice_muted")

    // Debounced form hints — only show after consistent detection,
    // and keep visible for at least 1.5s once shown.
    @State private var stableHints: [String] = []
    @State private var lastHintShowedAt: Date = .distantPast
    @State private var hintCandidates: [String: Int] = [:]   // hint → frame count
    private let hintMinFrames = 6        // ~0.2s at 30fps
    private let hintMinVisibleSeconds: Double = 1.5

    /// Parse the exercise reps to extract duration in seconds if it's a timed
    /// move (e.g. "30 sec", "60 sec"). For rep-based moves the timer is a
    /// generous safety cap — the work phase actually ends as soon as the user
    /// hits the rep target.
    private var workSeconds: Int {
        let s = exercise.reps.lowercased()
        if s.contains("sec") || s.contains("seconds") {
            return parseFirstInt(s) ?? 30
        }
        if s.contains("min") {
            return (parseFirstInt(s) ?? 1) * 60
        }
        // A hold detected by NAME (plank, wall sit…) with no explicit time
        // gets a sane 30-second hold — never a rep countdown.
        if isHoldByName { return 30 }
        // Rep-based — 60s safety cap per set
        return 60
    }

    private var isTimedExercise: Bool {
        let s = exercise.reps.lowercased()
        if s.contains("sec") || s.contains("min") { return true }
        return isHoldByName
    }

    /// Isometric holds where the user stays still — no reps, just a timed
    /// countdown. Detected by name so a "Plank" with reps like "60" or "3"
    /// is never mistaken for a rep-based move.
    private var isHoldByName: Bool {
        let n = exercise.name.lowercased()
        return n.contains("plank") || n.contains("hold") || n.contains("wall sit")
            || n.contains("dead hang") || n.contains("hollow") || n.contains("l-sit")
            || n.contains("l sit") || n.contains("superman") || n.contains("wall squat")
            || n.contains("isometric") || n.contains("bridge hold")
    }

    /// Rounds to run. Honors the user's explicit round count (the Edit sheet
    /// writes it straight here, 1–10). Rest happens BETWEEN rounds, so a single
    /// round naturally means no rest at all. We only fall back to a default when
    /// the count is unset/zero — never override a real choice.
    private var effectiveRounds: Int {
        max(1, exercise.sets)
    }

    /// "max" / "failure" / "max reps" — no fixed target, user goes until done.
    private var isMaxReps: Bool {
        let s = exercise.reps.lowercased()
        return s.contains("max") || s.contains("failure") || s.contains("amrap")
    }

    /// The single fixed rep target. Handles legacy "8-12" strings by taking
    /// the higher number (closer to the user's actual ceiling). Returns nil
    /// when the exercise is "max" / "failure" — no target to hit.
    private var repTarget: Int? {
        if isMaxReps { return nil }
        let s = exercise.reps
        if s.contains("-") {
            let parts = s.split(separator: "-").compactMap { Int($0.filter(\.isNumber)) }
            return parts.max()
        }
        return parseFirstInt(s)
    }

    private func parseFirstInt(_ s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    enum Phase {
        case waiting        // person not detected yet
        case getReady       // person detected, 3-2-1 countdown
        case working        // doing the exercise
        case resting        // between sets
        case done           // all sets complete
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewLayer(session: pose.captureSession)
                .ignoresSafeArea()

            // Dense, real-time skeleton from Vision joints. Green = rep
            // will count (form is 90%+ correct). Red = rep won't count.
            SkeletonOverlay(joints: pose.jointPositions,
                            formIsGood: pose.formIsGood)
                .ignoresSafeArea()

            // Dim overlay for HUD readability — applied AFTER the
            // skeleton so the camera dims but the bones stay vibrant.
            Color.black.opacity(0.18).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 16) {
                topBar
                Spacer()
                centerContent
                Spacer()
                if !stableHints.isEmpty && phase == .working {
                    formHintsRow
                }
                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Camera-denied overlay — replaces the permanent black preview
            // with a clear explanation and a one-tap Settings link.
            if pose.cameraAuthDenied {
                cameraDeniedOverlay
            }
        }
        .onAppear {
            // Lock to portrait — capture is hard-coded portrait and the
            // skeleton overlay doesn't account for landscape rotation.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
        .task {
            configureWorkoutAudio()
            pose.resetForExercise(exercise.name)
            await pose.start()
        }
        .onDisappear {
            // Restore all orientations when leaving the live workout.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
            }
            // Leaving early does NOT complete the exercise — it only counts
            // when the user actually hits their target / finishes the rounds.
            speech.stopSpeaking(at: .immediate)
            deactivateWorkoutAudio()
            pose.stop()
            timerCancellable?.invalidate()
        }
        .onChange(of: pose.motionConfidence) { _, newValue in
            if phase == .waiting && newValue > 0.6 && pose.personInFrame {
                startGetReady()
            }
        }
        // Every detected rep → haptic + spoken count so the user KNOWS the
        // ML is tracking them, not just running a timer. Then check for
        // target completion (only when there IS a numeric target).
        .onChange(of: pose.repCount) { _, newCount in
            guard phase == .working, !isTimedExercise else { return }
            PulseHaptics.light()
            speakNumber(newCount)
            if let target = repTarget, newCount >= target {
                PulseHaptics.success()
                finishCurrentPhase()
            } else if newCount > 0 && newCount % 5 == 0 {
                // Mid-set encouragement — keep the energy up during the work.
                speak(Self.encouragements.randomElement() ?? "Keep going")
            }
        }
        // Debounce form hints — don't flash on/off every frame.
        .onChange(of: pose.formHints) { _, raw in
            updateStableHints(from: raw)
        }
        // Speak form hints aloud when they STAY stable for >1.5s (the
        // debounce). Coach-style correction over the camera feed.
        .onChange(of: stableHints) { _, hints in
            guard phase == .working, let topHint = hints.first else { return }
            speak(topHint)
        }
    }

    /// True for exercises where the user is on the ground / parallel to
    /// it, so the camera cannot realistically capture the full body.
    /// We suppress the "step back" banner for these.
    private func requiresGroundPosture(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("push") || n.contains("dip") || n.contains("plank")
            || n.contains("bridge") || n.contains("crunch") || n.contains("sit-up")
            || n.contains("sit up") || n.contains("leg raise") || n.contains("burpee")
    }

    /// Coach-style banner above the controls. Used for form + framing cues.
    private func coachBanner(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.stand")
                .font(.system(size: 13, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(color))
        .transition(.opacity)
    }

    /// Speak just the count number — "one", "two", "three"…
    private func speakNumber(_ n: Int) {
        guard !voiceMuted else { return }
        let utterance = AVSpeechUtterance(string: "\(n)")
        utterance.voice = Self.naturalVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05  // snappier
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        speech.speak(utterance)
    }

    // MARK: - Subviews

    private var cameraDeniedOverlay: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.white.opacity(0.85))
                Text("Camera access needed")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Text("Pulse uses your camera to count reps and coach your form. Turn it on in Settings to start this workout.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                // X = abandon. Does NOT mark the exercise complete — only
                // genuinely finishing (hitting the target) counts.
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")

            // Mute / unmute the spoken coach voice. Your music keeps playing
            // either way — this only silences the talking.
            Button {
                toggleVoiceMuted()
            } label: {
                Image(systemName: voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(voiceMuted ? .white.opacity(0.55) : .white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(.leading, 8)
            .accessibilityLabel(voiceMuted ? "Unmute coach voice" : "Mute coach voice")

            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(exercise.name.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1.2)
                Text("ROUND \(currentSet) OF \(effectiveRounds) · \(isTimedExercise ? (isHoldByName ? "HOLD" : "WORK") : exercise.reps)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch phase {
        case .waiting:
            waitingView
        case .getReady, .working, .resting:
            timerView
        case .done:
            doneView
        }
    }

    private var waitingView: some View {
        let coach = ExerciseCoaching.forExercise(named: exercise.name)
        return VStack(spacing: 16) {
            Image(systemName: coach.movement.symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(.white)
            Text("SET UP · \(coach.movement.title.uppercased())")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(PulseColors.signal)

            // Per-exercise camera onboarding — how to place the phone, frame
            // yourself, and how this move is tracked. Mirrors the detector.
            VStack(alignment: .leading, spacing: 11) {
                onboardRow("iphone", coach.cameraPlacement)
                onboardRow("camera.viewfinder", coach.framing)
                onboardRow(coach.isAutoCounted ? "number.circle" : "timer", coach.countingHint)
            }
            .padding(14)
            .frame(maxWidth: 330, alignment: .leading)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(pose.personInFrame ? "Get in position…" : "Step into the frame")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
            // Motion confidence bar — fills as user starts moving
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(width: 220, height: 6)
                Capsule().fill(PulseColors.signal)
                    .frame(width: 220 * CGFloat(pose.motionConfidence), height: 6)
                    .animation(.easeOut(duration: 0.2), value: pose.motionConfidence)
            }
            Text(pose.personInFrame
                 ? (coach.isAutoCounted ? "Start moving — we'll auto-start the timer"
                                        : "Get into the hold — we'll start the countdown")
                 : "Camera is looking for you")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func onboardRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PulseColors.signal)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var timerView: some View {
        VStack(spacing: 14) {
            Text(phase == .resting ? "REST" : phase == .getReady ? "GET READY" : "GO")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(phase == .resting ? .white : PulseColors.signal)
                .tracking(2.5)

            if phase == .working && !isTimedExercise {
                // Rep-based: the REP COUNT is the hero number. Elapsed time is a
                // small readout that counts up with no cap — the set ends only on
                // the rep target (auto) or when you tap "Done".
                Text("\(pose.repCount)")
                    .font(.system(size: 130, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                if let target = repTarget {
                    Text("OF \(target) REPS · \(clockString(secondsRemaining))")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(pose.repCount >= target ? PulseColors.signal : .white.opacity(0.85))
                } else {
                    Text("REPS · \(clockString(secondsRemaining))")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                    Text("MAX — TAP DONE WHEN FINISHED")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.55))
                }
            } else {
                // Countdown hero — get-ready (3-2-1), timed hold, or rest.
                Text("\(secondsRemaining)")
                    .font(.system(size: 130, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                if phase == .resting {
                    Text("Round \(currentSet + 1) up next")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(PulseColors.signal)
            Text("EXERCISE COMPLETE")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white)
            Text("Great work. Nice form.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 46)
                    .background(PulseColors.signal)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    private var formHintsRow: some View {
        VStack(spacing: 6) {
            ForEach(stableHints, id: \.self) { hint in
                Text(hint.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(PulseColors.signal.opacity(0.85))
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stableHints)
    }

    /// Promote raw per-frame hints into "stable" hints only after they've been
    /// seen for `hintMinFrames` frames in a row, and keep them visible for at
    /// least `hintMinVisibleSeconds` before retracting.
    private func updateStableHints(from raw: [String]) {
        // Count how many frames each candidate has been present
        let rawSet = Set(raw)
        for hint in rawSet {
            hintCandidates[hint, default: 0] += 1
        }
        // Decay counters for hints no longer present
        for key in hintCandidates.keys where !rawSet.contains(key) {
            hintCandidates[key] = max(0, (hintCandidates[key] ?? 0) - 1)
        }
        let promoted = hintCandidates.filter { $0.value >= hintMinFrames }.map(\.key)

        // Stickiness: once a stable hint is showing, keep it visible for at
        // least hintMinVisibleSeconds before swapping or clearing.
        let now = Date()
        let elapsed = now.timeIntervalSince(lastHintShowedAt)
        if stableHints.isEmpty {
            if !promoted.isEmpty {
                stableHints = promoted.sorted()
                lastHintShowedAt = now
            }
        } else if elapsed >= hintMinVisibleSeconds {
            // Only swap once we've shown the current hint long enough.
            let newHints = promoted.sorted()
            if newHints != stableHints {
                stableHints = newHints
                lastHintShowedAt = now
            }
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            // Live rest control — shorten/extend, or pause/resume the rest timer.
            if phase == .resting {
                restAdjustButton("−15s") { secondsRemaining = max(1, secondsRemaining - 15) }
                restAdjustButton(timerPaused ? "Resume" : "Pause") { timerPaused.toggle() }
                restAdjustButton("+15s") { secondsRemaining += 15 }
            }
            // Finish the set early / skip the rest.
            if phase == .working || phase == .resting {
                Button {
                    finishCurrentPhase()
                } label: {
                    Text(phase == .working ? "Done" : "Skip rest")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            // Manually start (fallback if pose detection fails)
            if phase == .waiting {
                Button {
                    startGetReady()
                } label: {
                    Text("Start now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(PulseColors.signal)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func restAdjustButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            PulseHaptics.light()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    // MARK: - Timer / Phase machine

    private func startGetReady() {
        phase = .getReady
        timerPaused = false
        secondsRemaining = 3
        speak("Get ready")
        runTimer { tick in
            if tick == 0 { startWorking() }
        }
    }

    private func startWorking() {
        phase = .working
        timerPaused = false
        pose.repCount = 0
        lastEncouragementAt = -1
        if isTimedExercise {
            // Timed hold: count DOWN the set duration and auto-finish at 0.
            secondsRemaining = workSeconds
            speak("Hold. \(workSeconds) seconds. Stay tight.")
            runTimer { remaining in
                announceTimed(remaining)
                if remaining == 0 { finishCurrentPhase() }
            }
        } else {
            // Rep-based: NO time cap. The seconds count UP as a stopwatch so you
            // see elapsed time but are never cut off — take as long as you need.
            // The set ends only when you hit the rep target (auto) or tap "Done".
            secondsRemaining = 0
            speak("Go")
            runCountUpTimer()
        }
    }

    /// Spoken callouts during a timed hold: countdown markers + a midpoint
    /// word of encouragement. No reps are ever announced for holds.
    private func announceTimed(_ remaining: Int) {
        switch remaining {
        case 30, 20, 15, 10: speak("\(remaining) seconds left")
        case 5: speak("Five. Finish strong")
        default: break
        }
        let mid = max(5, workSeconds / 2)
        if remaining == mid && lastEncouragementAt != mid {
            lastEncouragementAt = mid
            speak(Self.encouragements.randomElement() ?? "Keep going")
        }
    }

    private static let encouragements = [
        "Stay strong", "You've got this", "Hold steady", "Keep breathing",
        "Almost there", "Don't quit now", "Brace your core", "Looking good"
    ]

    private func startResting() {
        let rest = max(0, exercise.restSeconds)
        // Rest = "None" (0) → no rest at all: skip straight to the next round.
        // Honor the EXACT chosen seconds otherwise (no hidden 15s floor).
        guard rest > 0 else { advanceSet(); return }
        phase = .resting
        timerPaused = false
        secondsRemaining = rest
        speak("Rest")
        runTimer { tick in
            if tick == 0 { advanceSet() }
        }
    }

    /// Rep-based work has no time cap — this counts UP (elapsed) purely for
    /// display, never auto-finishing. The set ends on the rep target or "Done".
    private func runCountUpTimer() {
        timerCancellable?.invalidate()
        timerCancellable = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async { secondsRemaining += 1 }
        }
    }

    /// m:ss for the elapsed-time readout on rep-based sets.
    private func clockString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func finishCurrentPhase() {
        timerCancellable?.invalidate()
        switch phase {
        case .working:
            if currentSet >= effectiveRounds {
                completeExercise()
            } else {
                startResting()
            }
        case .resting:
            advanceSet()
        default: break
        }
    }

    private func advanceSet() {
        currentSet += 1
        if currentSet > effectiveRounds {
            completeExercise()
        } else {
            startWorking()
        }
    }

    /// Centralized exit point — fires the parent callback so the workout sheet
    /// can mark this exercise off (and auto-finish the workout if it was the
    /// last one). Then auto-dismisses after a short "exercise complete" beat.
    private func completeExercise() {
        phase = .done
        speak("Exercise complete. Great work.")
        onComplete?(exercise.id)
        // Auto-dismiss after ~2.5s so the user can see the "complete" screen
        // briefly without having to tap Done. The parent will handle "next
        // exercise" or "whole workout done" UI in response to the callback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if phase == .done { dismiss() }
        }
    }

    private func runTimer(onTick: @escaping (Int) -> Void) {
        timerCancellable?.invalidate()
        timerCancellable = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            DispatchQueue.main.async {
                // Paused (rest Pause button) → hold the clock, keep the timer alive.
                if timerPaused { return }
                if secondsRemaining > 0 {
                    secondsRemaining -= 1
                    if secondsRemaining <= 3 && secondsRemaining > 0 {
                        playTick()
                    }
                    onTick(secondsRemaining)   // fire every tick (incl. 0)
                    if secondsRemaining == 0 {
                        playBell()
                        t.invalidate()
                    }
                }
            }
        }
    }

    // MARK: - Audio cues

    /// Picks the most natural-sounding voice available on the device.
    /// Priority order: Premium > Enhanced > Default. Within each tier, prefers
    /// modern named voices (Ava, Samantha, Joelle, Daniel) over generic ones.
    private static var naturalVoice: AVSpeechSynthesisVoice? = {
        let langPrefix = Locale.current.language.languageCode?.identifier ?? "en"
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(langPrefix)
        }
        // Names that sound the most natural on modern iOS
        let preferredNames = ["Ava", "Samantha", "Zoe", "Allison", "Joelle", "Karen", "Moira", "Daniel", "Tom"]

        // 1) Premium quality + preferred name
        if let v = allVoices.first(where: { $0.quality == .premium && preferredNames.contains($0.name) }) {
            return v
        }
        // 2) Any Premium
        if let v = allVoices.first(where: { $0.quality == .premium }) {
            return v
        }
        // 3) Enhanced + preferred name
        if let v = allVoices.first(where: { $0.quality == .enhanced && preferredNames.contains($0.name) }) {
            return v
        }
        // 4) Any Enhanced
        if let v = allVoices.first(where: { $0.quality == .enhanced }) {
            return v
        }
        // 5) Anything matching locale, or system default
        return allVoices.first ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// Configure the audio session so the user's OWN music keeps playing at full
    /// volume — never ducked — while the coach voice mixes in on top.
    ///
    /// `.mixWithOthers` WITHOUT `.duckOthers` is the key: we never pull their
    /// music down, so they can blast it at max during rest sets. `.default` mode
    /// (not `.voicePrompt`) avoids the system's automatic voice-prompt ducking.
    /// (iOS exposes no public API to set a custom partial-duck level for other
    /// apps, so "music full, voice on top" is the loudest-music option.)
    private func configureWorkoutAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func deactivateWorkoutAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Toggle the spoken coach voice on/off, persist the choice, and cut any
    /// in-progress speech instantly so muting feels immediate.
    private func toggleVoiceMuted() {
        voiceMuted.toggle()
        UserDefaults.standard.set(voiceMuted, forKey: "pulse_live_voice_muted")
        if voiceMuted { speech.stopSpeaking(at: .immediate) }
        PulseHaptics.light()
    }

    private func speak(_ text: String) {
        guard !voiceMuted else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.naturalVoice
        // Slower than default, slight pitch lift = warmer + more "coach" feel
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.02
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        speech.speak(utterance)
    }

    private func playTick() {
        AudioServicesPlaySystemSound(1057) // ms-soft "Tink"
    }

    private func playBell() {
        AudioServicesPlaySystemSound(1322) // ms-loud "Sherwood"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Camera preview

import AVFoundation
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    var orientation: AVCaptureVideoOrientation = .portrait

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        applyOrientation(v)
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Keep the preview in lock-step with the capture orientation so the
        // skeleton overlay (normalized coords) stays aligned in both modes.
        applyOrientation(uiView)
    }

    private func applyOrientation(_ v: PreviewView) {
        if let c = v.videoPreviewLayer.connection, c.isVideoOrientationSupported {
            c.videoOrientation = orientation
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
