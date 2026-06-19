import SwiftUI

enum MomentumState {
    case rising, steady, declining

    var label: String {
        switch self {
        case .rising: return "Rising"
        case .steady: return "Steady"
        case .declining: return "Declining"
        }
    }

    var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .rising: return PulseColors.success
        case .steady: return PulseColors.primary
        case .declining: return PulseColors.warning
        }
    }
}

struct MomentumIndicator: View {
    let state: MomentumState

    var body: some View {
        HStack(spacing: PulseSpacing.xs) {
            Image(systemName: state.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(state.label)
                .font(PulseTypography.labelMedium)
        }
        .foregroundColor(state.color)
        .padding(.horizontal, PulseSpacing.md)
        .padding(.vertical, PulseSpacing.sm - 1)
        .background(PulseColors.surfaceElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )
    }
}
