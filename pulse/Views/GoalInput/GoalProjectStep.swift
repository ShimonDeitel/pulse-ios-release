import SwiftUI

/// Project-specific questions shown only when GoalInputViewModel.flavor == "project".
/// Inserted as an extra step in GoalInputFlowView's TabView for project goals.
struct GoalProjectStep: View {
    @Bindable var viewModel: GoalInputViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PulseSpacing.xxl) {
                Text("Tell us about the project".localized)
                    .font(PulseTypography.headlineLarge)
                    .foregroundColor(PulseColors.textPrimary)
                    .headlineTracking()

                // End state
                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("WHAT DOES \"DONE\" LOOK LIKE".localized)
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()
                    TextField(
                        "",
                        text: $viewModel.projectEndState,
                        prompt: Text("e.g. Manuscript submitted, defended thesis, app on App Store")
                            .foregroundColor(PulseColors.textTertiary),
                        axis: .vertical
                    )
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textPrimary)
                    .lineLimit(2...4)
                    .padding(PulseSpacing.lg)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                }

                // Deliverables
                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("KEY DELIVERABLES".localized)
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()
                    TextField(
                        "",
                        text: $viewModel.projectDeliverables,
                        prompt: Text("e.g. outline, draft 1, draft 2, edit, cover, publish")
                            .foregroundColor(PulseColors.textTertiary),
                        axis: .vertical
                    )
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textPrimary)
                    .lineLimit(2...4)
                    .padding(PulseSpacing.lg)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                    Text("Comma-separated. Skip if you want the AI to figure them out.".localized)
                        .font(PulseTypography.labelSmall)
                        .foregroundColor(PulseColors.textTertiary)
                }

                // Phases
                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    Text("PHASES (OPTIONAL)".localized)
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(PulseColors.textTertiary)
                        .eyebrowTracking()
                    TextField(
                        "",
                        text: $viewModel.projectPhases,
                        prompt: Text("e.g. research, plan, build, polish, ship")
                            .foregroundColor(PulseColors.textTertiary),
                        axis: .vertical
                    )
                    .font(PulseTypography.bodyMedium)
                    .foregroundColor(PulseColors.textPrimary)
                    .lineLimit(2...3)
                    .padding(PulseSpacing.lg)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                }

                // Complexity
                VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                    HStack {
                        Text("COMPLEXITY".localized)
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(PulseColors.textTertiary)
                            .eyebrowTracking()
                        Spacer()
                        Text("\(Int(viewModel.projectComplexity))/10")
                            .font(PulseTypography.monoCaption)
                            .foregroundColor(PulseColors.signal)
                    }
                    Slider(value: $viewModel.projectComplexity, in: 1...10, step: 1)
                        .tint(PulseColors.signal)
                    Text("1 = a weekend hack, 10 = a multi-year endeavor.".localized)
                        .font(PulseTypography.labelSmall)
                        .foregroundColor(PulseColors.textTertiary)
                }
            }
            .padding(PulseSpacing.screenEdge)
        }
    }
}
