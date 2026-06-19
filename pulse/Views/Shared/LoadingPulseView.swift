import SwiftUI

// MARK: - Loading Spinner
// Reference: .spin class — small border spinner with ink top color.

struct LoadingPulseView: View {
    @State private var rotate = false
    var message: String = "Analyzing..."
    var color: Color = PulseColors.ink

    var body: some View {
        VStack(spacing: PulseSpacing.lg) {
            ZStack {
                Circle()
                    .stroke(PulseColors.muted2, lineWidth: 2)
                    .frame(width: 14, height: 14)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(rotate ? 360 : 0))
            }
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotate = true
                }
            }

            Text(message)
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.muted)
        }
    }
}

// MARK: - Large Loading View (for full-screen states)

struct LoadingPulseLargeView: View {
    @State private var rotate = false
    var message: String = "Analyzing..."

    var body: some View {
        VStack(spacing: PulseSpacing.xxl) {
            ZStack {
                Circle()
                    .stroke(PulseColors.muted2.opacity(0.3), lineWidth: 2)
                    .frame(width: 48, height: 48)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(PulseColors.signal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(rotate ? 360 : 0))
            }
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotate = true
                }
            }

            Text(message)
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.muted)
        }
    }
}
