import SwiftUI

struct ProgressRingView: View {
    let progress: Double
    var size: CGFloat = 60
    var lineWidth: CGFloat = 5
    var color: Color = PulseColors.signal
    var showLabel: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(PulseColors.muted2.opacity(0.3), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(PulseAnimations.reveal, value: progress)

            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(size > 50 ? PulseTypography.monoCaption : PulseTypography.monoTag)
                    .monoTracking()
                    .foregroundColor(PulseColors.ink)
            }
        }
        .frame(width: size, height: size)
    }
}
