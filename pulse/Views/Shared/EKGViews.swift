import SwiftUI

// MARK: - EKG Trace View
// The signature visual element. Renders a heartbeat monitor trace
// with completed "beats" as spikes and a live cursor.

struct EKGTraceView: View {
    var width: CGFloat = 320
    var height: CGFloat = 70
    var beats: [CGFloat] = [0.2, 0.45, 0.7]
    var progress: CGFloat = 1.0
    var color: Color = PulseColors.signal
    var animated: Bool = true

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let baseline = h * 0.55
            let spikeH = h * 0.45

            // Grid lines (very subtle)
            let gridSpacing: CGFloat = 20
            for x in stride(from: CGFloat(0), through: w, by: gridSpacing) {
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: h))
                context.stroke(gridPath, with: .color(PulseColors.ink.opacity(0.04)), lineWidth: 0.5)
            }
            for y in stride(from: CGFloat(0), through: h, by: gridSpacing) {
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: w, y: y))
                context.stroke(gridPath, with: .color(PulseColors.ink.opacity(0.04)), lineWidth: 0.5)
            }

            // Baseline
            var basePath = Path()
            basePath.move(to: CGPoint(x: 0, y: baseline))
            basePath.addLine(to: CGPoint(x: w, y: baseline))
            context.stroke(basePath, with: .color(PulseColors.ink.opacity(0.07)), lineWidth: 0.5)

            // EKG trace
            var path = Path()
            path.move(to: CGPoint(x: 0, y: baseline))
            var x: CGFloat = 0
            let drawEnd = animated ? drawProgress * w : w

            for beat in beats {
                let bx = beat * w
                guard bx <= drawEnd else { break }

                // Gentle wobble before beat
                while x < bx - 16 && x < drawEnd {
                    x += 8
                    let dy = sin(x * 0.18) * 1.5
                    path.addLine(to: CGPoint(x: min(x, drawEnd), y: baseline + dy))
                }

                if bx <= drawEnd {
                    // Classic EKG spike: small down, big up, big down, small up
                    path.addLine(to: CGPoint(x: bx - 8, y: baseline + 4))
                    path.addLine(to: CGPoint(x: bx - 4, y: baseline - spikeH * 0.85))
                    path.addLine(to: CGPoint(x: bx, y: baseline + spikeH * 0.55))
                    path.addLine(to: CGPoint(x: bx + 4, y: baseline - 5))
                    path.addLine(to: CGPoint(x: bx + 8, y: baseline))
                    x = bx + 8
                }
            }

            // Trail after last beat
            while x < drawEnd {
                x += 8
                let dy = sin(x * 0.18) * 1.5
                path.addLine(to: CGPoint(x: min(x, drawEnd), y: baseline + dy))
            }

            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))

            // Live cursor dot
            if progress < 1.0 {
                let cursorX = progress * w
                // Cursor line
                var cursorPath = Path()
                cursorPath.move(to: CGPoint(x: cursorX, y: 0))
                cursorPath.addLine(to: CGPoint(x: cursorX, y: h))
                context.stroke(cursorPath, with: .color(color.opacity(0.3)), lineWidth: 1)

                // Cursor dot
                let dotRect = CGRect(x: cursorX - 3, y: baseline - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            if animated {
                withAnimation(.easeOut(duration: 2.4)) {
                    drawProgress = 1.0
                }
            }
        }
    }
}

// MARK: - Mini Pulse (Inline Separator)
// Tiny EKG blip used as visual separators and brand marks.

struct MiniPulseView: View {
    var width: CGFloat = 60
    var height: CGFloat = 16
    var color: Color = PulseColors.signal
    var opacity: Double = 0.4

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h / 2))
            path.addLine(to: CGPoint(x: w * 0.35, y: h / 2))
            path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.15))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.85))
            path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.3))
            path.addLine(to: CGPoint(x: w * 0.65, y: h / 2))
            path.addLine(to: CGPoint(x: w, y: h / 2))
            context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}

// MARK: - EKG Divider
// Full-width section divider with heartbeat blip.

struct EKGDivider: View {
    var color: Color = PulseColors.ink
    var opacity: Double = 0.18

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h: CGFloat = 22
            let mid = h / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: mid))
            path.addLine(to: CGPoint(x: w * 0.375, y: mid))
            path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.18))
            path.addLine(to: CGPoint(x: w * 0.425, y: h * 0.82))
            path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.27))
            path.addLine(to: CGPoint(x: w * 0.475, y: mid))
            path.addLine(to: CGPoint(x: w, y: mid))
            context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 22)
    }
}

// MARK: - Live Dot
// Pulsing indicator for active/live states.

struct LiveDot: View {
    var color: Color = PulseColors.signal
    var size: CGFloat = 8

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 3.2, height: size * 3.2)
                .scaleEffect(pulsing ? 1 : 0.3)
                .opacity(pulsing ? 0 : 0.7)

            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Check Circle
// Checkbox with scribbled check mark feel.

struct CheckCircle: View {
    let isChecked: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isChecked ? PulseColors.mono : PulseColors.muted2, lineWidth: 1.5)
                .background(Circle().fill(isChecked ? PulseColors.mono : Color.clear))
                .frame(width: size, height: size)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(PulseColors.onMono)
            }
        }
    }
}
