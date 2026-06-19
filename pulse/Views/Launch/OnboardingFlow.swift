import SwiftUI
import CoreData

// MARK: - Onboarding Flow (CloudDesign: 3 slides with progress bars)

struct OnboardingFlow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.managedObjectContext) private var viewContext
    @State private var currentSlide = 0

    private let slides: [(eyebrow: String, title: String, body: String, visual: String)] = [
        (
            "PULSE / 01",
            "Set a goal.",
            "Anything. Vague. Specific. Insane. Tiny. Write it down \u{2014} Pulse takes it from there.",
            "goal"
        ),
        (
            "PULSE / 02",
            "We break it into pulses.",
            "Hundreds of pulses. Or ten. Or three. Scheduled around your deadline, your hours, your life.",
            "pulses"
        ),
        (
            "PULSE / 03",
            "Show up. Repeat.",
            "A coach in your pocket. Real steps, real proof — one pulse at a time.",
            "pulses"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // ── Progress bars ────────────────────────────────
            HStack(spacing: 6) {
                ForEach(0..<slides.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index <= currentSlide ? PulseColors.mono : PulseColors.ink.opacity(0.12))
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.3), value: currentSlide)
                }
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.top, 8)

            // ── Visual area ────────────────────────────────
            Spacer()

            Group {
                switch slides[currentSlide].visual {
                case "goal":
                    onbVisualGoal
                case "pulses":
                    onbVisualPulses
                default:
                    onbVisualGoal
                }
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .id(currentSlide)

            Spacer()

            // ── Text block ─────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                Text(slides[currentSlide].eyebrow)
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.muted)
                    .padding(.bottom, 16)

                Text(slides[currentSlide].title)
                    .font(.system(size: 42, weight: .semibold))
                    .tracking(-1.68) // -0.04em
                    .foregroundColor(PulseColors.ink)
                    .padding(.bottom, 14)

                Text(slides[currentSlide].body)
                    .font(.system(size: 17))
                    .foregroundColor(PulseColors.muted)
                    .lineSpacing(17 * 0.45 - 17)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.bottom, 12)

            // ── Actions: Skip + Continue/Get started ──────
            HStack(alignment: .center) {
                Button {
                    skipToAuth()
                } label: {
                    Text("Skip".localized)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PulseColors.muted)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)
                }

                Spacer()

                if currentSlide < slides.count - 1 {
                    Button {
                        withAnimation(PulseAnimations.gentle) {
                            currentSlide += 1
                        }
                        PulseHaptics.light()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Continue".localized)
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(-0.15)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(PulseColors.onMono)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(PulseColors.mono)
                        .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                    }
                } else {
                    Button {
                        skipToAuth()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Get Started".localized)
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(-0.15)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(PulseColors.onMono)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(PulseColors.mono)
                        .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.bottom, 18)
        }
        .background(PulseColors.background.ignoresSafeArea())
    }

    private func skipToAuth() {
        // Mark onboarding seen, go to auth. Persist durably so killing the app
        // on the auth screen doesn't replay onboarding on the next cold launch
        // (mirrors AuthWelcomeView): UserDefaults flag for the synchronous read,
        // plus the Core Data flag so older/reconciling installs agree too.
        appState.isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "pulse_onboarding_complete")
        let profile = UserProfile.fetchOrCreate(in: viewContext)
        profile.onboardingCompleted = true
        try? viewContext.save()
        PulseHaptics.light()
    }

    // MARK: - Visual: Goal card

    private var onbVisualGoal: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR GOAL")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.muted)

                Text("Make $1,000")
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-1.28)
                    .foregroundColor(PulseColors.ink)
                + Text("|")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(PulseColors.muted2)

                HStack(spacing: 8) {
                    chipOutline("freelance")
                    chipOutline("90 days")
                }
            }
            .padding(PulseSpacing.cardPadding)
            .background(PulseColors.paper)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

            // LIVE badge rotated
            HStack(spacing: 4) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("LIVE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(PulseColors.signal)
            .clipShape(Capsule())
            .rotationEffect(.degrees(8))
            .offset(x: 8, y: -10)
        }
        .frame(maxWidth: 320)
    }

    // MARK: - Visual: Pulses (EKG card-ink)

    private var onbVisualPulses: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("23 PULSES \u{00B7} 90 DAYS")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(PulseColors.signal).frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(PulseTypography.monoCaption)
                            .monoTracking()
                            .foregroundColor(PulseColors.signal)
                    }
                }

                EKGTraceView(
                    width: 280,
                    height: 88,
                    beats: [0.08, 0.22, 0.36, 0.5, 0.64, 0.78, 0.92],
                    progress: 0.42,
                    color: PulseColors.signal,
                    animated: false
                )

                HStack {
                    Text("D-0")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text("D-90")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(18)
            .background(PulseColors.mono)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))

            HStack(spacing: 8) {
                ForEach(["Pitch 3 leads", "Update LinkedIn", "Build portfolio"], id: \.self) { text in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("0\(["Pitch 3 leads", "Update LinkedIn", "Build portfolio"].firstIndex(of: text)! + 1)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(PulseColors.muted)
                        Text(text)
                            .font(.system(size: 11.5))
                            .foregroundColor(PulseColors.ink)
                            .lineSpacing(11.5 * 0.3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(PulseColors.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                }
            }
        }
        .frame(maxWidth: 320)
    }


    private func chipOutline(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(PulseColors.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 9999, style: .continuous)
                    .stroke(PulseColors.hairStrong, lineWidth: 1)
            )
    }
}

// Shared component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(PulseColors.signal)
                .frame(width: 44, height: 44)
                .background(PulseColors.signal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PulseColors.ink)
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(PulseColors.muted)
            }
            Spacer()
        }
    }
}
