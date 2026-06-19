import SwiftUI

/// Small badge that sits next to a display name to signal the user's tier.
/// • Free → grey "F" pill
/// • Pro  → gold "P" pill
struct TierBadge: View {
    let tier: SubscriptionTier
    var compact: Bool = false

    var body: some View {
        switch tier {
        case .free:
            Text("F")
                .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                .foregroundColor(PulseColors.muted)
                .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
                .background(PulseColors.muted.opacity(0.15))
                .clipShape(Circle())
        case .pro:
            Text("P")
                .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: compact ? 16 : 18, height: compact ? 16 : 18)
                .background(PulseColors.gold)
                .clipShape(Circle())
        }
    }
}

/// Convenience — a "name + badge" inline pair used in lists and headers.
struct UserNameWithBadge: View {
    let name: String
    let tier: SubscriptionTier
    var nameFont: Font = .system(size: 15, weight: .semibold)
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Text(name)
                .font(nameFont)
                .foregroundColor(PulseColors.ink)
                .lineLimit(1)
            TierBadge(tier: tier, compact: compact)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        UserNameWithBadge(name: "Alex", tier: .free)
        UserNameWithBadge(name: "Shimon", tier: .pro)
    }
    .padding()
}
