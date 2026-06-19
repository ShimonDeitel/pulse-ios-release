import SwiftUI

struct QuickActionBar: View {
    @Environment(AppState.self) private var appState
    @State private var showingUpgrade = false
    @State private var showingTransformDisclaimer = false
    // Observe the @Observable subscription singleton so the lock clears the
    // moment the user upgrades to Pro mid-session.
    @State private var subscription = SubscriptionManager.shared

    /// Count active goals to enforce the free cap (1 active goal at a time).
    @FetchRequest(sortDescriptors: []) private var allGoals: FetchedResults<Goal>
    private var activeGoalCount: Int { allGoals.filter { $0.statusEnum == .active }.count }

    /// Transform creates a transformation GOAL. AI is free for everyone now, so
    /// the only gate is the free goal cap — at the cap, tapping opens the paywall.
    private var transformUnlocked: Bool {
        subscription.canCreateGoal(currentCount: activeGoalCount)
    }

    var body: some View {
        HStack(spacing: 4) {
            QuickActionItem(icon: "chart.line.uptrend.xyaxis", label: "Progress".localized) {
                appState.showingProgress = true
            }
            QuickActionItem(icon: "timer", label: "Focus".localized) {
                appState.showingFocusMode = true
            }
            QuickActionItem(icon: "bubble.left.fill", label: "Chat".localized) {
                appState.selectedTab = 2
            }
            QuickActionItem(icon: "camera.fill", label: "Transform".localized, locked: !transformUnlocked) {
                if transformUnlocked {
                    showingTransformDisclaimer = true
                } else {
                    showingUpgrade = true
                }
            }
            QuickActionItem(icon: "plus", label: "New Goal".localized, emphasized: true) {
                appState.showingGoalTypePicker = true
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView()
        }
        .sheet(isPresented: $showingTransformDisclaimer) {
            GoalRealityCheckView(
                goalType: .transformation,
                onContinue: {
                    showingTransformDisclaimer = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        appState.showingPhotoTransformation = true
                    }
                },
                onCancel: {
                    showingTransformDisclaimer = false
                }
            )
        }
    }
}

struct QuickActionItem: View {
    let icon: String
    let label: String
    /// The primary action (New Goal) gets a filled red tile to stand out.
    var emphasized: Bool = false
    /// Pro-only actions show a small lock badge so it's clear before tapping.
    var locked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            PulseHaptics.light()
            action()
        }) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(emphasized ? PulseColors.signal : PulseColors.signal.opacity(0.10))
                            .frame(width: 46, height: 46)
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: emphasized ? .bold : .semibold))
                            .foregroundColor(emphasized ? .white : PulseColors.signal)
                    }
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(PulseColors.gold, in: Circle())
                            .overlay(Circle().stroke(PulseColors.paper, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PulseColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(QuickActionButtonStyle())
    }
}

struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? PulseAnimations.pressScale : 1)
            .opacity(configuration.isPressed ? PulseAnimations.pressOpacity : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}
