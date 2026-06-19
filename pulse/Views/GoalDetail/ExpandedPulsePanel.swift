import SwiftUI
import PhotosUI

/// The expanded section of a pulse row when the user taps to expand it.
/// Always shows Instructions and Proof (with fallback text if the AI returned empty),
/// gives an inline TextField for typing proof right in the row, and offers two
/// equally-sized buttons: Mark Complete + Upload Proof.
struct ExpandedPulsePanel: View {
    @ObservedObject var step: DailyTask
    @ObservedObject var goal: Goal
    let done: Bool
    /// Called when user taps Mark Complete. Receives whatever they typed (may be empty).
    let onComplete: (_ proofNote: String) -> Void
    /// Called when user taps Upload Proof — parent shows photo picker / camera sheet.
    let onUploadProof: () -> Void

    @State private var proofInput: String = ""
    @State private var isFindingVideo = false

    /// Proof is required to complete a pulse — either typed text here, or a
    /// photo via "Upload Proof".
    private var hasTypedProof: Bool {
        !proofInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var instructionsText: String {
        let raw = step.howTo
        if !raw.isEmpty { return raw }
        // Only mention "Ask AI" to Pro/Max — Free has no AI.
        if SubscriptionManager.shared.hasAIGeneration {
            return "Complete this pulse on your own terms. Tap \"Ask AI\" below if you want a specific breakdown."
        }
        return "Complete this pulse on your own terms."
    }

    private var proofText: String {
        let raw = step.proofRequired
        if !raw.isEmpty { return raw }
        return "Describe what you did, or upload a photo as proof."
    }

    /// Category-specific example for the "Your proof" placeholder, so the user
    /// sees a realistic prompt for the goal they're actually working on.
    private var proofPlaceholder: String {
        let category = goal.categoryEnum
        switch category {
        case .fitness:
            return "e.g. \"Ran 1.2km in 8 min, felt strong\""
        case .health:
            return "e.g. \"Drank 2L water, slept 7.5 hrs\""
        case .learning:
            return "e.g. \"Finished chapter 4, took 2 pages of notes\""
        case .finance:
            return "e.g. \"Saved $50 today, skipped takeout\""
        case .career:
            return "e.g. \"Sent 5 applications, called 1 recruiter\""
        case .creative:
            return "e.g. \"Wrote 800 words, sketched 3 thumbnails\""
        case .social:
            return "e.g. \"Texted a friend, hosted dinner for 4\""
        case .mindfulness:
            return "e.g. \"15 min meditation, felt calmer after\""
        case .personal:
            return "e.g. \"Did the thing — here's how it went\""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Instructions (always visible) ─────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("INSTRUCTIONS".localized)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
                Text(instructionsText)
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Proof required (always visible) ──────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("PROOF REQUIRED".localized)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
                Text(proofText)
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Watch a video (always visible) ────────────────
            // Finds the best explainer video on the internet for THIS pulse and
            // opens it. Pro/Max with a search key get the exact best video; Free
            // users get a YouTube search for the pulse. Always does something.
            watchVideoButton

            // ── Estimated time ────────────────────────────────
            if step.estimatedMinutes > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(PulseColors.muted)
                    Text("~\(step.estimatedMinutes) " + "minutes".localized)
                        .font(.system(size: 12.5))
                        .foregroundColor(PulseColors.muted)
                }
            }

            // ── Inline proof input (user types here directly) ─
            if !done {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR PROOF".localized)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(PulseColors.muted)

                    TextField(
                        "",
                        text: $proofInput,
                        prompt: Text(proofPlaceholder)
                            .foregroundColor(PulseColors.muted),
                        axis: .vertical
                    )
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.ink)
                    .lineLimit(2...5)
                    .padding(10)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PulseColors.hair, lineWidth: 0.5)
                    )
                }

                // ── Action buttons — SAME width via .frame(maxWidth: .infinity) ──
                HStack(spacing: 10) {
                    Button {
                        guard hasTypedProof else { return }
                        onComplete(proofInput.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text("Mark Complete".localized)
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(hasTypedProof ? PulseColors.signal : PulseColors.signal.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .disabled(!hasTypedProof)

                    Button {
                        onUploadProof()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13))
                            Text("Upload Proof".localized)
                        }
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(PulseColors.signal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(PulseColors.signal.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(PulseColors.signal.opacity(0.35), lineWidth: 1)
                        )
                    }
                }

                if !hasTypedProof {
                    Text("Add proof to complete — type it above, or tap Upload Proof to add a photo.")
                        .font(.system(size: 11))
                        .foregroundColor(PulseColors.muted)
                }
            }
        }
    }

    // MARK: - Watch a video

    /// Video-icon button: finds + opens the best explainer video for this pulse.
    private var watchVideoButton: some View {
        Button {
            guard !isFindingVideo else { return }
            PulseHaptics.light()
            isFindingVideo = true
            let pulseTitle = step.titleValue
            let goalTitle = goal.titleValue
            Task {
                await PulseVideoService.findAndOpen(pulseTitle: pulseTitle, goalTitle: goalTitle)
                isFindingVideo = false
            }
        } label: {
            HStack(spacing: 7) {
                if isFindingVideo {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PulseColors.signal)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 14))
                }
                Text(isFindingVideo ? "Finding best video…".localized : "Watch a video".localized)
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(PulseColors.signal)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(PulseColors.signal.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(PulseColors.signal.opacity(0.35), lineWidth: 1)
            )
        }
        .disabled(isFindingVideo)
    }
}
