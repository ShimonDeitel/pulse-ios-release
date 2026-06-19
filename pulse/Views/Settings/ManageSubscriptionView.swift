import SwiftUI

/// Manage the user's Pulse subscription — all details and cancellation in one
/// place. Shows the plan, price, status, and the exact next-billing (or
/// trial-end) date. Cancelling stops billing: no charge next period, access
/// continues until the current period ends, then drops to Free.
struct ManageSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscription = SubscriptionManager.shared
    @State private var store = StoreManager.shared
    /// Presents the paywall so a lapsed (Free) user can resubscribe to Pro.
    @State private var showUpgrade = false
    @State private var isOpening = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PulseSpacing.xl) {
                    planCard
                    billingCard
                    actions
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, PulseSpacing.section)
            }
            .pulseScreen()
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(PulseColors.ink)
                }
            }
            .sheet(isPresented: $showUpgrade) { UpgradeView() }
            // Retry the live product load so a failed initial fetch (offline at
            // launch) recovers and the localized price replaces the tier fallback.
            .task { await StoreManager.shared.loadProducts() }
        }
    }

    // MARK: - Plan card

    private var planCard: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: subscription.isCancelled ? "clock.badge.xmark" : "checkmark.seal.fill")
                    .foregroundColor(statusColor)
                Text(subscription.currentTier.displayName)
                    .font(PulseTypography.titleMedium)
                    .foregroundColor(PulseColors.textPrimary)
                Spacer()
                Text(statusText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(statusColor)
            }
            Text(planBlurb)
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textSecondary)
        }
        .padding(PulseSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
            .stroke(statusColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Billing card

    private var billingCard: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("BILLING DETAILS")
                .font(PulseTypography.eyebrow).eyebrowTracking()
                .foregroundColor(PulseColors.textTertiary)

            detailRow("Plan", subscription.currentTier.displayName)
            detailRow("Price", livePrice)
            detailRow("Auto-renew", subscription.autoRenew ? "On" : "Off")

            if subscription.isOnTrial, let t = subscription.trialEndDate {
                detailRow("Free trial ends", dateStr(t))
                if subscription.autoRenew {
                    detailRow("First charge", "\(dateStr(t)) · \(livePrice)")
                } else {
                    detailRow("Access until", dateStr(t))
                }
            } else if let nb = subscription.nextBillingDate {
                if subscription.autoRenew {
                    detailRow("Next billing", "\(dateStr(nb)) · \(livePrice)")
                } else {
                    detailRow("Access until", dateStr(nb))
                }
            }

            detailRow("Billed by", "Apple (your Apple ID)")

            Text(billingNote)
                .font(PulseTypography.labelSmall)
                .foregroundColor(PulseColors.textTertiary)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PulseSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if subscription.isPro {
            // Apple owns billing: cancelling, resuming, or changing a plan all
            // happen in the system manage-subscriptions sheet. We open it and
            // re-read the verified entitlement when the user returns. Whether
            // auto-renew is on (active) or off (cancelled, access until period
            // end), the destination is the same Apple sheet — so a cancelled
            // sub reads "Manage subscription", not a misleading "Resume".
            Button {
                PulseHaptics.light()
                isOpening = true
                Task { await store.showManageSubscriptions(); isOpening = false }
            } label: {
                Group {
                    if isOpening {
                        ProgressView().tint(subscription.autoRenew ? PulseColors.signal : .white)
                    } else {
                        Text(subscription.autoRenew ? "Cancel subscription" : "Manage subscription")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(subscription.autoRenew ? PulseColors.signal : .white)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(subscription.autoRenew ? PulseColors.signal.opacity(0.10) : PulseColors.signal)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(subscription.autoRenew ? PulseColors.signal.opacity(0.35) : .clear, lineWidth: 1))
            }
            .disabled(isOpening)

            Text("Manage everything — cancel, resume, or change your plan — in your Apple subscriptions.")
                .font(PulseTypography.labelSmall)
                .foregroundColor(PulseColors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            #if DEBUG
            // DEBUG-only: the dev Pro unlock has no real Apple subscription, so
            // Apple's manage sheet can't cancel it — this drops straight back to
            // Free for tier testing. Compiled out of TestFlight/App Store builds.
            if SubscriptionManager.shared.isDebugProUnlocked {
                Button {
                    SubscriptionManager.shared.debugTogglePro()
                    PulseHaptics.light()
                } label: {
                    Text("DEBUG: Switch to Free (testing only)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.yellow)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
            }
            #endif
        } else {
            // Fully lapsed (no current entitlement): give the user a way back to
            // Pro instead of stranding them with only a note.
            Button {
                PulseHaptics.light()
                showUpgrade = true
            } label: {
                Text("Resubscribe to Pro")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(PulseColors.signal)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("You're on the Free plan — no billing.")
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Copy

    /// Live, localized Pro price + billing period from StoreKit (e.g. "$9.99/month").
    /// Falls back to the static tier price only when the live product hasn't
    /// loaded yet (e.g. offline at launch) — `displayPrice` is never empty (it
    /// has a hardcoded USD literal fallback), so we gate on `proProduct == nil`
    /// to avoid showing USD pricing to a non-USD storefront.
    private var livePrice: String {
        StoreManager.shared.proProduct == nil ? subscription.currentTier.price : "\(store.displayPrice)/\(store.billingPeriodText)"
    }

    private var statusText: String {
        if !subscription.isPro { return "FREE" }
        if subscription.isCancelled { return "CANCELLED" }
        if subscription.isOnTrial { return "FREE TRIAL" }
        return "ACTIVE"
    }

    private var statusColor: Color {
        if !subscription.isPro || subscription.isCancelled { return PulseColors.muted }
        if subscription.isOnTrial { return PulseColors.signal }
        return PulseColors.gold
    }

    private var planBlurb: String {
        if subscription.isCancelled {
            return "Cancelled — you keep full access until your period ends, then you move to Free. You won't be charged again."
        }
        if subscription.isOnTrial {
            return "You're on a free trial with unlimited goals and Primary Access — priority AI."
        }
        if subscription.isPro {
            return "Thanks for backing Pulse. You have unlimited goals and Primary Access — priority AI."
        }
        return "You're on the Free plan — the full AI coach plus one active goal. Upgrade for unlimited goals and Primary Access — priority AI."
    }

    private var billingNote: String {
        if subscription.isCancelled {
            return "Auto-renew is off, so you won't be charged again. You keep \(subscription.currentTier.displayName) until the date above, then automatically move to Free."
        }
        if subscription.isOnTrial {
            return "You're in a free trial — no charge yet. If you don't cancel before it ends, your \(subscription.currentTier.displayName) subscription begins at \(livePrice) and renews automatically. Cancel anytime below."
        }
        return "Your \(subscription.currentTier.displayName) subscription renews automatically at \(livePrice) unless cancelled. Cancelling stops billing — you won't be charged next period."
    }

    private func dateStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textSecondary)
            Spacer()
            Text(value)
                .font(PulseTypography.bodySmall.weight(.semibold))
                .foregroundColor(PulseColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
