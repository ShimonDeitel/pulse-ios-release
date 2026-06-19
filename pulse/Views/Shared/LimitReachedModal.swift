import SwiftUI

/// Shown when AI is temporarily unavailable: a Pro user who hit their monthly
/// AI budget, or a Free user when the free AI is busy (too many people using it
/// at once). AI is free for everyone, so the Free case is a "try again / get
/// Primary Access" nudge, not an AI block. Pulls them straight into the upgrade
/// flow at the moment of highest intent.
struct LimitReachedModal: View {
    let currentTier: SubscriptionTier
    let suggestedUpgrade: SubscriptionTier?
    let onUpgrade: (SubscriptionTier) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(PulseColors.signal.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(PulseColors.signal)
            }
            .padding(.top, 24)

            VStack(spacing: 6) {
                Text(currentTier == .free ? "Too many people are using Pulse" : "You've used your monthly limit")
                    .font(.system(size: 21, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(PulseColors.ink)
                Text(currentTier == .free
                     ? "A lot of people are using the free AI right now. Try again in a moment — or upgrade to Pro for Primary Access: priority AI that never waits in line."
                     : "You're on \(currentTier.displayName) and you've used your AI allowance for now — it refreshes as your plan renews.")
                    .font(.system(size: 14))
                    .foregroundColor(PulseColors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let upgrade = suggestedUpgrade {
                // Free users already get AI for free, so their upgrade reason is
                // Primary Access (priority AI), not "unlocking" AI. Guard the
                // "Nx more" math for any other tier with a 0 budget so the ratio
                // can't divide by zero (→ Int(.infinity) crash).
                let comparison = currentTier == .free
                    ? "Primary Access — priority AI, no waiting"
                    : (currentTier.monthlyAIBudgetUSD > 0
                        ? "\(Int(upgrade.monthlyAIBudgetUSD / currentTier.monthlyAIBudgetUSD))x more AI than your current plan"
                        : "Primary Access — priority AI, no waiting")
                VStack(spacing: 10) {
                    Button {
                        onUpgrade(upgrade)
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: upgrade.badgeIcon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Upgrade to \(upgrade.displayName)")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text(comparison)
                                .font(.system(size: 12))
                                .opacity(0.85)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PulseColors.signal)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    Text("\(upgradePriceText(for: upgrade)) — cancel anytime")
                        .font(.system(size: 12))
                        .foregroundColor(PulseColors.muted)
                }
            } else {
                Text("Resets on the 1st of next month.")
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.muted)
                    .padding(.vertical, 12)
            }

            Button {
                onClose()
            } label: {
                Text(suggestedUpgrade != nil ? "Not now" : "Got it")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(PulseColors.muted)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 8)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    /// Live, localized price + billing period from StoreKit (e.g. "$9.99/month").
    /// `displayPrice` can never actually be empty (it falls back to a hardcoded
    /// USD literal), so the old `.isEmpty` check was dead and would have shown
    /// USD to a non-USD user when the live product hadn't loaded. Gate on the
    /// product instead: only use the live price once StoreKit has resolved it,
    /// otherwise fall back to the tier's localized static price.
    private func upgradePriceText(for tier: SubscriptionTier) -> String {
        let store = StoreManager.shared
        return store.proProduct == nil ? tier.price : "\(store.displayPrice)/\(store.billingPeriodText)"
    }
}
