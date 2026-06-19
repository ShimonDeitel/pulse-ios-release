import WidgetKit
import SwiftUI

// MARK: - Progress Widget (shows goal progress)

struct PulseProgressEntry: TimelineEntry {
    let date: Date
    let goalTitle: String
    let completedPulses: Int
    let totalPulses: Int
    let daysRemaining: Int
    let probability: Int
}

struct PulseProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseProgressEntry {
        PulseProgressEntry(
            date: Date(),
            goalTitle: "Launch my app",
            completedPulses: 15,
            totalPulses: 30,
            daysRemaining: 14,
            probability: 72
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseProgressEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseProgressEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> PulseProgressEntry {
        let defaults = UserDefaults(suiteName: "group.com.shimondeitel.pulsegoals")
        return PulseProgressEntry(
            date: Date(),
            goalTitle: defaults?.string(forKey: "widget_goal_title") ?? "No active goal",
            completedPulses: defaults?.integer(forKey: "widget_completed_pulses") ?? 0,
            totalPulses: defaults?.integer(forKey: "widget_total_pulses") ?? 1,
            daysRemaining: defaults?.integer(forKey: "widget_days_remaining") ?? 0,
            probability: defaults?.integer(forKey: "widget_probability") ?? 0
        )
    }
}

struct PulseProgressWidgetView: View {
    var entry: PulseProgressEntry
    @Environment(\.widgetFamily) var family

    private var progress: Double {
        guard entry.totalPulses > 0 else { return 0 }
        return Double(entry.completedPulses) / Double(entry.totalPulses)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "91231C"))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Text(entry.goalTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "91231C"))
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(entry.completedPulses)/\(entry.totalPulses)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(entry.daysRemaining)d left")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: "91231C"), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    Text("DONE")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            // Right: details
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.goalTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(entry.completedPulses)/\(entry.totalPulses)", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Label("\(entry.daysRemaining)d", systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Label("\(entry.probability)%", systemImage: "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "91231C"))
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "91231C"))
                            .frame(width: geo.size.width * progress, height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(16)
    }
}

struct PulseProgressWidget: Widget {
    let kind: String = "PulseProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProgressProvider()) { entry in
            PulseProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Goal Progress")
        .description("Track your active goal progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Color extension for widget
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
