import SwiftUI

struct MissionControlHeader: View {
    let profile: UserProfile

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                    Text(greeting)
                        .font(PulseTypography.bodyLarge)
                        .foregroundColor(PulseColors.textSecondary)

                    Text(profile.displayNameValue)
                        .font(PulseTypography.displaySmall)
                        .foregroundColor(PulseColors.textPrimary)
                        .displayTracking()
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(PulseColors.surfaceContainer)
                        .frame(width: 48, height: 48)

                    Text(String(profile.displayNameValue.prefix(1)).uppercased())
                        .font(PulseTypography.headlineSmall)
                        .foregroundColor(PulseColors.primary)
                }
            }

            HStack(spacing: PulseSpacing.sm) {
                StatChip(icon: "flame.fill", value: "\(profile.currentStreak)", color: PulseColors.warning)
                StatChip(icon: "star.fill", value: "\(profile.totalXP) XP", color: PulseColors.primary)
                StatChip(icon: "chart.bar.fill", value: "Lv.\(profile.currentLevel)", color: PulseColors.secondary)
            }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }
}

struct NeonStatChip: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: PulseSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(PulseTypography.labelMedium)
                .foregroundColor(PulseColors.textPrimary)
        }
        .padding(.horizontal, PulseSpacing.md)
        .padding(.vertical, PulseSpacing.sm)
        .background(PulseColors.surfaceElevated)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )
    }
}

typealias StatChip = NeonStatChip
