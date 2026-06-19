import SwiftUI
import CoreData

// MARK: - Tour Step Model

struct TourStep: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let tabIndex: Int
}

// MARK: - Onboarding Tour View (CloudDesign tokens)

struct OnboardingTourView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @State private var currentStep = 0
    @State private var appeared = false
    @State private var cardScale: CGFloat = 0.8
    @State private var cardOpacity: CGFloat = 0

    private let steps: [TourStep] = [
        TourStep(
            icon: "house",
            iconColor: PulseColors.signal,
            title: "Mission Control",
            subtitle: "HOME",
            description: "See all your active goals, streaks, and daily pulses at a glance. Your command center.",
            tabIndex: 0
        ),
        TourStep(
            icon: "target",
            iconColor: PulseColors.signal,
            title: "Goal Engine",
            subtitle: "GOALS",
            description: "Create goals and get AI-generated roadmaps with milestones, daily pulses, and probability scores.",
            tabIndex: 1
        ),
        TourStep(
            icon: "bubble.left.and.bubble.right",
            iconColor: PulseColors.signal,
            title: "AI Chat",
            subtitle: "CHAT",
            description: "Chat with an AI that knows your goals, progress, and obstacles. Ten unique personalities.",
            tabIndex: 2
        ),
        TourStep(
            icon: "person",
            iconColor: PulseColors.signal,
            title: "Your Profile",
            subtitle: "ME",
            description: "Track your stats, manage settings, and upgrade to Pro for the full experience.",
            tabIndex: 3
        ),
    ]

    private var step: TourStep { steps[currentStep] }
    private var isLastStep: Bool { currentStep == steps.count - 1 }

    var body: some View {
        ZStack {
            PulseColors.background.ignoresSafeArea()

            // Subtle glow
            RadialGradient(
                colors: [PulseColors.signal.opacity(0.06), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 250
            )
            .ignoresSafeArea()
            .offset(y: -60)

            VStack(spacing: 0) {
                // ── Progress bars + Skip ──────────────────
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(index <= currentStep ? PulseColors.mono : PulseColors.ink.opacity(0.12))
                            .frame(height: 3)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 8)

                HStack {
                    Spacer()
                    Button("Skip") { completeTour() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(PulseColors.muted)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 8)

                Spacer()

                // ── Icon + text ─────────────────────────────
                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .fill(PulseColors.signal.opacity(0.08))
                            .frame(width: 120, height: 120)

                        Image(systemName: step.icon)
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(PulseColors.signal)
                    }
                    .scaleEffect(cardScale)

                    VStack(spacing: 10) {
                        Text(step.subtitle)
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.signal)

                        Text(step.title)
                            .font(.system(size: 32, weight: .semibold))
                            .tracking(-1.28)
                            .foregroundColor(PulseColors.ink)

                        Text(step.description)
                            .font(.system(size: 16))
                            .foregroundColor(PulseColors.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 8)
                    }
                    .opacity(cardOpacity)
                }
                .padding(.horizontal, 32)

                Spacer()

                // ── Step counter ──────────────────────────
                Text("\(currentStep + 1) of \(steps.count)")
                    .font(PulseTypography.monoCaption)
                    .monoTracking()
                    .foregroundColor(PulseColors.muted)
                    .padding(.bottom, 12)

                // ── Navigation ────────────────────────────
                HStack(spacing: 10) {
                    if currentStep > 0 {
                        Button { navigateBack() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 15, weight: .semibold))
                                    .tracking(-0.15)
                            }
                            .foregroundColor(PulseColors.ink)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(PulseColors.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9999, style: .continuous)
                                    .stroke(PulseColors.hairStrong, lineWidth: 1)
                            )
                        }
                    }

                    Button {
                        if isLastStep { completeTour() } else { navigateForward() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isLastStep ? "Get started" : "Next")
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(-0.15)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(PulseColors.onMono)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(PulseColors.mono)
                        .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, 40)
            }
        }
        .onAppear { animateIn() }
    }

    // MARK: - Navigation

    private func navigateForward() {
        PulseHaptics.light()
        withAnimation(.easeIn(duration: 0.15)) {
            cardScale = 0.9; cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentStep += 1
            animateIn()
        }
    }

    private func navigateBack() {
        PulseHaptics.light()
        withAnimation(.easeIn(duration: 0.15)) {
            cardScale = 0.9; cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentStep -= 1
            animateIn()
        }
    }

    private func animateIn() {
        cardScale = 0.8; cardOpacity = 0
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { cardScale = 1.0 }
        withAnimation(.easeOut(duration: 0.4).delay(0.1)) { cardOpacity = 1.0 }
        appeared = true
    }

    private func completeTour() {
        PulseHaptics.success()
        let profile = UserProfile.fetchOrCreate(in: viewContext)
        profile.onboardingTourCompleted = true
        try? viewContext.save()
        appState.showOnboardingTour = false
    }
}
