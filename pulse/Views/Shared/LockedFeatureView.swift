import SwiftUI

/// Full-screen "this feature is locked" state shown to free users in place of a
/// Pro/Max-only feature. Gold-accented to match premium status, with a direct
/// upgrade path. Use when an entire screen is gated.
struct LockedFeatureView: View {
    let title: String
    let message: String
    var icon: String = "lock.fill"
    @State private var showingUpgrade = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(PulseColors.gold.opacity(0.12)).frame(width: 84, height: 84)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(PulseColors.gold)
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(PulseColors.gold)
                    .clipShape(Circle())
                    .offset(x: 28, y: 28)
            }
            Text(title)
                .font(PulseTypography.titleLarge)
                .foregroundColor(PulseColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PulseSpacing.xl)
            Text("This feature is locked. Upgrade to Pro or Max to unlock it.")
                .font(PulseTypography.labelMedium)
                .foregroundColor(PulseColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PulseSpacing.xl)
            Button {
                showingUpgrade = true
                PulseHaptics.medium()
            } label: {
                Text("Upgrade").frame(maxWidth: .infinity)
            }
            .buttonStyle(M3SignalButton())
            .padding(.horizontal, PulseSpacing.section)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pulseScreen()
        .sheet(isPresented: $showingUpgrade) { UpgradeView() }
    }
}

/// Compact inline "PRO" lock pill — drop next to a Pro-only control.
struct ProLockPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
            Text("PRO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.8)
        }
        .foregroundColor(PulseColors.gold)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(PulseColors.gold.opacity(0.12))
        .clipShape(Capsule())
    }
}
