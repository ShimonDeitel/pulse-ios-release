import SwiftUI

// MARK: - Background Views
// Reference: Warm cream background, radial gradient stage.

struct AnimatedGradientBackground: View {
    var body: some View {
        PulseColors.cream.ignoresSafeArea()
    }
}

/// Radial gradient stage — subtle warmth like the reference .stage class
struct StageBackground: View {
    var body: some View {
        ZStack {
            PulseColors.cream2
            RadialGradient(
                colors: [PulseColors.cream, PulseColors.cream2],
                center: .init(x: 0.3, y: 0),
                startRadius: 0,
                endRadius: UIScreen.main.bounds.height * 0.6
            )
        }
        .ignoresSafeArea()
    }
}

/// Ink background — for dark full-screen overlays (onboarding, paywall)
struct InkBackground: View {
    var body: some View {
        PulseColors.mono.ignoresSafeArea()
    }
}

struct ParticleBackground: View {
    let count: Int
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) * 1.618
                    let x = (sin(t * 0.1 + seed) * 0.5 + 0.5) * size.width
                    let y = (cos(t * 0.08 + seed * 1.3) * 0.5 + 0.5) * size.height
                    let pSize = 1.5 + sin(seed) * 1.0
                    let opacity = 0.15 + sin(t * 0.5 + seed) * 0.1
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: pSize, height: pSize)),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}
