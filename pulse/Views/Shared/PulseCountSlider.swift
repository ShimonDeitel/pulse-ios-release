import SwiftUI

/// "How many pulses?" slider used on goal-creation screens. Default 20, up to
/// 150. Shows a tappable "Recommended" marker the user can snap to. The AI
/// generates exactly this many pulses (batched behind the scenes).
struct PulseCountSlider: View {
    @Binding var count: Double
    /// Optional AI-suggested count, shown as a tappable marker.
    var recommended: Int? = nil

    private let range: ClosedRange<Double> = 5...150

    var body: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("HOW MANY PULSES")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.textTertiary)
                Spacer()
                Text("\(Int(count))")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(PulseColors.signal)
                    .contentTransition(.numericText())
            }

            Slider(value: $count, in: range, step: 5)
                .tint(PulseColors.signal)

            HStack {
                Text("\(Int(range.lowerBound))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
                Spacer()
                if let r = recommended {
                    Button {
                        withAnimation(PulseAnimations.gentle) {
                            count = Double(min(max(r, Int(range.lowerBound)), Int(range.upperBound)))
                        }
                        PulseHaptics.light()
                    } label: {
                        Text("Recommended: \(r)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(PulseColors.signal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PulseColors.signal.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(Int(range.upperBound))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PulseColors.muted)
            }

            Text("More pulses = a longer, more detailed roadmap. You can always add more later.")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }
}
