import WidgetKit
import SwiftUI

/// Shared brand palette + helpers for every Pulse home-screen widget.
/// (Color(hex:) lives in PulseProgressWidget.swift — same target/module.)
enum PW {
    static let accent = Color(hex: "91231C")   // Pulse maroon
    static let gold   = Color(hex: "C8911C")   // XP / level gold
    static let green  = Color(hex: "2E7D32")   // healthy / rising
    static let suite  = "group.com.shimondeitel.pulsegoals"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suite) }
}

/// Reusable empty state shown when there is no active goal yet.
struct PWEmpty: View {
    var icon: String = "target"
    var line: String = "No active goal"
    var sub: String = "Open Pulse to start one"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(PW.accent)
            Text(line)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            Text(sub)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

/// A thin rounded progress bar used across several widgets.
struct PWBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(tint)
                    .frame(width: geo.size.width * min(1, max(0, progress)), height: height)
            }
        }
        .frame(height: height)
    }
}
