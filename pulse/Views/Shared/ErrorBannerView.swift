import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var icon: String = "exclamationmark.circle.fill"

    var body: some View {
        HStack(spacing: PulseSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(message)
                .font(PulseTypography.bodySmall)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(PulseColors.signal)
        .padding(.horizontal, PulseSpacing.lg)
        .padding(.vertical, PulseSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.signal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: M3Shapes.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: M3Shapes.medium, style: .continuous)
                .stroke(PulseColors.signal.opacity(0.15), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
