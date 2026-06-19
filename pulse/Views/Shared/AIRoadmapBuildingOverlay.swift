import SwiftUI

/// Full-screen overlay shown during goal creation while the AI builds the
/// personalized roadmap. Replaces the old "seed templates then fire-and-forget
/// AI" pattern — the user now sees a clear "we're working on this" state
/// instead of being dropped on hand-crafted templates that may or may not get
/// silently swapped later.
///
/// Cycles through reassuring status messages so the wait feels purposeful.
struct AIRoadmapBuildingOverlay: View {
    let title: String
    @State private var statusIndex = 0
    @State private var rotation: Double = 0

    private let messages = [
        "Reading your goal…",
        "Designing your roadmap…",
        "Tuning the difficulty…",
        "Spacing your pulses across the deadline…",
        "Adding the proof requirements…",
        "Almost done…"
    ]

    var body: some View {
        ZStack {
            // Dim the screen behind so the form is visibly disabled.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Animated ring
                ZStack {
                    Circle()
                        .stroke(PulseColors.signal.opacity(0.20), lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .trim(from: 0.0, to: 0.35)
                        .stroke(PulseColors.signal,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(rotation))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: rotation)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(PulseColors.signal)
                }

                VStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Building your AI roadmap")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(messages[statusIndex])
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(statusIndex)

                Text("This usually takes 10-30 seconds.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PulseColors.signal.opacity(0.25), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 36)
        }
        .onAppear {
            rotation = 360
            cycleMessages()
        }
    }

    private func cycleMessages() {
        Task {
            for i in 1..<messages.count {
                try? await Task.sleep(nanoseconds: 4_500_000_000) // 4.5s per message
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        statusIndex = i
                    }
                }
            }
        }
    }
}

/// Recovery dialog shown when AI completely fails during goal creation.
/// Gives the user three explicit choices instead of silently falling back.
/// Optionally surfaces the underlying error string so we can actually see
/// what went wrong (timeout, rate limit, malformed JSON, etc.).
struct AIRoadmapFailureDialog: View {
    let onRetry: () -> Void
    let onCancel: () -> Void
    var errorDetail: String? = nil

    /// True when the failure is a usage/rate limit, so we show the honest
    /// "Usage limit hit" copy rather than a generic error.
    private var isUsageLimit: Bool {
        let d = errorDetail ?? ""
        return d.localizedCaseInsensitiveContains("usage limit")
            || d.localizedCaseInsensitiveContains("rate")
            || d.localizedCaseInsensitiveContains("allowance")
            || d.localizedCaseInsensitiveContains("Pulse Pro")
            || d.localizedCaseInsensitiveContains("resets tomorrow")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: isUsageLimit ? "hourglass" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(PulseColors.signal)
                Text(isUsageLimit ? "Usage limit hit" : "Couldn't reach the AI")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text(isUsageLimit
                     ? "You've hit your AI usage limit, so we can't generate your plan right now. Every plan in Pulse is built live by AI — we never show you a canned, fake plan. Try again in a bit."
                     : "We couldn't reach the AI to build your personalized plan. Pulse only ever shows you real AI-generated plans, so nothing was created. Please try again.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if let detail = errorDetail, !detail.isEmpty, !isUsageLimit {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(spacing: 10) {
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(PulseColors.signal)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(PulseColors.signal.opacity(0.25), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
        }
    }
}
