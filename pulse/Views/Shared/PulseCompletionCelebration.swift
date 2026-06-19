import SwiftUI
import UIKit

/// Wrapper so a UIImage can drive a `.sheet(item:)`.
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Full-screen celebration overlay shown when the user completes a pulse.
/// Confetti + big "+XP" + "Pulse N complete" message + haptics.
/// Auto-dismisses after ~2.4s.
struct PulseCompletionCelebration: View {
    let pulseNumber: Int
    let xpGained: Int
    let totalXP: Int
    let nextPulseTitle: String?
    let didLevelUp: Bool
    let newLevel: Int
    var goalTitle: String? = nil
    var authorId: String = "me"
    var authorName: String = "You"
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var confettiPhase: Double = 0
    @State private var xpCount: Int = 0
    @State private var systemShareImage: IdentifiableImage?

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Confetti canvas
            ConfettiView(phase: confettiPhase)
                .allowsHitTesting(false)

            VStack(spacing: 24) {
                // Big mark
                ZStack {
                    Circle()
                        .fill(PulseColors.signal)
                        .frame(width: 110, height: 110)
                        .shadow(color: PulseColors.signal.opacity(0.45), radius: 30, y: 8)
                    Image(systemName: "checkmark")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(scale)

                // Title
                VStack(spacing: 6) {
                    Text("PULSE \(String(format: "%02d", pulseNumber))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(2)
                    Text(didLevelUp ? "LEVEL UP" : "PULSE COMPLETE")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.white)
                        .tracking(0.5)
                }

                // XP gain
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundColor(PulseColors.signal)
                    Text("+\(xpCount) XP")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial.opacity(0.7))
                .clipShape(Capsule())

                if didLevelUp {
                    Text("You're now level \(newLevel)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }

                if let next = nextPulseTitle {
                    VStack(spacing: 4) {
                        Text("NEXT PULSE")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                            .tracking(1.5)
                        Text(next)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 32)
                }

                HStack(spacing: 10) {
                    Button { shareElsewhere() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold))
                            Text("Share")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 130, height: 46)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                    }

                    Button { onDismiss() } label: {
                        Text("Keep going")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(PulseColors.signal)
                            .frame(width: 150, height: 46)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .opacity(opacity)
            .scaleEffect(opacity == 0 ? 0.9 : 1.0)
        }
        .sheet(item: $systemShareImage) { wrap in
            ActivityShareView(items: [shareText, wrap.image])
        }
        .onAppear {
            // Pop in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                scale = 1.0
                opacity = 1.0
            }
            // Confetti
            withAnimation(.linear(duration: 2.4)) {
                confettiPhase = 1.0
            }
            // XP count-up
            animateXP()
            // Haptics
            PulseHaptics.success()
            // Auto-dismiss (but not while the user is sharing)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                if systemShareImage == nil {
                    onDismiss()
                }
            }
        }
    }

    private func animateXP() {
        let steps = 20
        let target = xpGained
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                withAnimation(.easeOut(duration: 0.04)) {
                    xpCount = (target * i) / steps
                }
            }
        }
    }

    // MARK: - Share

    private var shareText: String {
        if let g = goalTitle, !g.isEmpty {
            return "Just completed Pulse \(pulseNumber) of \"\(g)\" on Pulse — +\(xpGained) XP and counting."
        }
        return "Just completed Pulse \(pulseNumber) on Pulse — +\(xpGained) XP and counting."
    }

    @MainActor private func renderCard() -> UIImage? {
        let card = MilestoneShareCard(pulseNumber: pulseNumber, xpGained: xpGained,
                                      goalTitle: goalTitle, didLevelUp: didLevelUp, newLevel: newLevel)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func shareElsewhere() {
        if let img = renderCard() { systemShareImage = IdentifiableImage(image: img) }
    }
}

// MARK: - Milestone share card (rendered to an image for story/post/share)

struct MilestoneShareCard: View {
    let pulseNumber: Int
    let xpGained: Int
    let goalTitle: String?
    let didLevelUp: Bool
    let newLevel: Int

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("PULSE")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .tracking(3).foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            Spacer()
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 96, height: 96)
                Image(systemName: "checkmark").font(.system(size: 46, weight: .bold)).foregroundColor(.white)
            }
            Text(didLevelUp ? "LEVEL UP" : "PULSE \(String(format: "%02d", pulseNumber)) COMPLETE")
                .font(.system(size: 24, weight: .heavy)).foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let g = goalTitle, !g.isEmpty {
                Text(g).font(.system(size: 16, weight: .medium)).foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            Text("+\(xpGained) XP")
                .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white)
            Spacer()
            Text("Made with Pulse").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.7))
        }
        .padding(28)
        .frame(width: 320, height: 480)
        .background(LinearGradient(colors: [PulseColors.signal, PulseColors.signal.opacity(0.72)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

// MARK: - System share sheet

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Goal completion celebration

struct GoalCompletionCelebration: View {
    let goalTitle: String
    let daysTaken: Int
    let totalPulses: Int
    let isFirst: Bool
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var confettiPhase: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture { onDismiss() }
            ConfettiView(phase: confettiPhase).allowsHitTesting(false)

            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(PulseColors.gold).frame(width: 120, height: 120)
                        .shadow(color: PulseColors.gold.opacity(0.5), radius: 30, y: 8)
                    Image(systemName: "trophy.fill").font(.system(size: 54, weight: .bold)).foregroundColor(.white)
                }
                .scaleEffect(scale)

                VStack(spacing: 8) {
                    Text(isFirst ? "YOUR FIRST GOAL" : "GOAL COMPLETE")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7)).tracking(2)
                    Text("Wow — you did it.")
                        .font(.system(size: 30, weight: .heavy)).foregroundColor(.white)
                    Text("\"\(goalTitle)\"")
                        .font(.system(size: 17, weight: .medium)).foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 28)
                }

                HStack(spacing: 28) {
                    stat("\(totalPulses)", "pulses")
                    stat("\(max(1, daysTaken))", daysTaken == 1 ? "day" : "days")
                }

                Text("You finished this goal in \(max(1, daysTaken)) \(daysTaken == 1 ? "day" : "days"). That's real momentum — set your next one.")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center).padding(.horizontal, 30)

                Button { onDismiss() } label: {
                    Text("Onward")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(PulseColors.ink)
                        .frame(width: 200, height: 48).background(.white).clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .opacity(opacity)
            .scaleEffect(opacity == 0 ? 0.9 : 1)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { scale = 1; opacity = 1 }
            withAnimation(.linear(duration: 2.6)) { confettiPhase = 1 }
            PulseHaptics.success()
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Lightweight confetti

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat            // 0...1 horizontal
    let delay: Double         // 0...0.6
    let driftX: CGFloat       // -1...1
    let rotation: Double      // start rotation degrees
    let color: Color
    let size: CGFloat
}

private struct ConfettiView: View {
    let phase: Double  // 0 to 1

    private static let pieces: [ConfettiPiece] = (0..<60).map { _ in
        ConfettiPiece(
            x: CGFloat.random(in: 0.05...0.95),
            delay: Double.random(in: 0...0.4),
            driftX: CGFloat.random(in: -0.15...0.15),
            rotation: Double.random(in: 0...360),
            color: [
                PulseColors.signal,
                Color(hex: "F4F1E8"),
                Color(hex: "C8B88A"),
                PulseColors.signal,
                .white
            ].randomElement()!,
            size: CGFloat.random(in: 5...10)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Self.pieces) { piece in
                    let local = max(0, min(1, (phase - piece.delay) / max(0.1, 1 - piece.delay)))
                    Rectangle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 0.45)
                        .rotationEffect(.degrees(piece.rotation + Double(local) * 540))
                        .position(
                            x: piece.x * geo.size.width + piece.driftX * geo.size.width * CGFloat(local),
                            y: -20 + CGFloat(local) * (geo.size.height + 60)
                        )
                        .opacity(local < 1 ? 1 - local * 0.2 : 0)
                }
            }
        }
        .ignoresSafeArea()
    }
}
