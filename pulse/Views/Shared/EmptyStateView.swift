import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: PulseSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(PulseColors.primary.opacity(0.06))
                    .frame(width: 88, height: 88)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(PulseColors.textTertiary)
            }

            VStack(spacing: PulseSpacing.sm) {
                Text(title)
                    .font(PulseTypography.headlineSmall)
                    .foregroundColor(PulseColors.textPrimary)

                Text(message)
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(M3FilledButton())
                    .padding(.horizontal, PulseSpacing.section)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, PulseSpacing.xxxl)
    }
}
