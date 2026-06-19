import SwiftUI

/// Honest reality-check + safety disclaimer shown before every goal is created.
///
/// Two jobs:
///   1. Set honest expectations — no app can guarantee you'll hit a big goal,
///      but consistent effort gives you a real shot. (User-requested framing.)
///   2. Surface the Terms §4 (AI is not professional advice) and §7 (health &
///      fitness) disclaimers at the point of decision — so the warnings aren't
///      buried in legalese. Health goals get the extra "see a physician" line.
///
/// Presented as a gate between picking a goal type and the creation form, so it
/// appears for EVERY goal, every time.
struct GoalRealityCheckView: View {
    let goalType: GoalType
    let onContinue: () -> Void
    let onCancel: () -> Void

    @State private var showingTerms = false

    /// Health-adjacent goals get the medical line + physician warning.
    private var isHealth: Bool { goalType == .transformation || goalType == .workout }
    /// Money / trading goals get a financial-risk line.
    private var isMoney: Bool { goalType == .money }
    /// AI is free for everyone; only Custom Workout stays manual on-device.
    /// `hasAIGeneration` is always true now — kept so the disclaimer copy can
    /// describe the AI-built plan accurately.
    private var hasAI: Bool { SubscriptionManager.shared.hasAIGeneration }
    /// Whether THIS goal actually uses AI. Custom Workout is always manual
    /// (built-in library + on-device skeleton), so it never claims AI — even
    /// for Pro users.
    private var usesAI: Bool { hasAI && goalType != .workout }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PulseSpacing.xl) {
                    header

                    point(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No guarantees — but a real shot",
                        body: "No app, and no plan, can promise you'll hit this goal. Big goals are hard and most people fall short the first time. But the people who show up every day genuinely change their lives — and that can be you. Pulse gives you a real chance, not a promise."
                    )

                    if goalType == .workout {
                        point(
                            icon: "figure.strengthtraining.traditional",
                            title: "You build it yourself — no AI",
                            body: "You hand-pick exercises into your own plan, and Pulse counts your reps on-device with the camera. No AI, no photos, no internet needed — and it's free."
                        )
                    } else if hasAI {
                        point(
                            icon: "sparkles",
                            title: "Your plan is AI-generated",
                            body: "Pulse uses AI to build your roadmap, pulses, and coaching. AI can be wrong, inaccurate, or miss your specific situation. Use your own judgment and double-check anything that matters."
                        )
                    } else {
                        point(
                            icon: "sparkles",
                            title: "Your plan is AI-generated",
                            body: "Pulse uses AI to build your roadmap, pulses, and coaching — free for everyone. AI can be wrong, inaccurate, or miss your specific situation. Use your own judgment and double-check anything that matters."
                        )
                    }

                    point(
                        icon: isHealth ? "cross.case" : "checkmark.seal",
                        title: isHealth ? "Not medical advice" : "Not professional advice",
                        body: healthOrAdviceBody
                    )

                    if isMoney {
                        point(
                            icon: "dollarsign.circle",
                            title: "Money goals carry real risk",
                            body: "Earnings, trading, and investing involve risk, including loss of capital. Pulse is not financial advice and results are never guaranteed. Only risk what you can afford to lose, and consult a licensed advisor for real financial decisions."
                        )
                    }

                    termsLine
                    buttons
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, PulseSpacing.section)
            }
            .pulseScreen()
            .navigationTitle("Before you commit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
            .sheet(isPresented: $showingTerms) {
                NavigationStack { TermsOfServiceView() }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(PulseColors.signal)
            Text("A quick, honest heads-up")
                .font(PulseTypography.titleLarge)
                .foregroundColor(PulseColors.textPrimary)
            Text(hasAI
                 ? "Read this before we build your \(goalType.displayName.lowercased()) plan."
                 : "Read this before you start your \(goalType.displayName.lowercased()).")
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.textSecondary)
        }
        .padding(.top, PulseSpacing.sm)
    }

    private func point(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: PulseSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(PulseColors.signal)
                .frame(width: 30, height: 30)
                .background(PulseColors.signal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: M3Shapes.small, style: .continuous))

            VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                Text(title)
                    .font(PulseTypography.labelLargeEmphasized)
                    .foregroundColor(PulseColors.textPrimary)
                Text(body)
                    .font(PulseTypography.bodySmall)
                    .foregroundColor(PulseColors.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var healthOrAdviceBody: String {
        if isHealth {
            return "Pulse is not a doctor, dietitian, or personal trainer, and this is not medical advice. Talk to a physician before starting any new exercise or diet — especially if you have an injury, a medical condition, or take medication. If you feel pain, dizziness, or anything wrong, stop and seek help."
        } else {
            return "Pulse is not a licensed professional. Nothing here is medical, legal, financial, or other professional advice. For real decisions about your health, money, or legal situation, consult a qualified professional."
        }
    }

    private var termsLine: some View {
        Button {
            showingTerms = true
            PulseHaptics.light()
        } label: {
            (Text("Continuing means you agree to the ")
                .foregroundColor(PulseColors.textTertiary)
             + Text("Terms of Use")
                .foregroundColor(PulseColors.signal)
             + Text(hasAI ? ", including the health and AI-output disclaimers."
                          : ", including the health disclaimers.")
                .foregroundColor(PulseColors.textTertiary))
                .font(PulseTypography.labelSmall)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
    }

    private var buttons: some View {
        VStack(spacing: PulseSpacing.sm) {
            Button {
                PulseHaptics.medium()
                onContinue()
            } label: {
                Text("I understand — let's build it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(M3SignalButton())

            Button {
                onCancel()
            } label: {
                Text("Not now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(M3GhostButton())
        }
        .padding(.top, PulseSpacing.sm)
    }
}
