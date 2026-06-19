import WidgetKit
import SwiftUI

// MARK: - Momentum Widget

struct PulseMomentumEntry: TimelineEntry {
    let date: Date
    let momentum: String   // "rising" | "steady" | "declining"
    let recent: Int
    let prior: Int
    let hasGoal: Bool
}

struct PulseMomentumProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseMomentumEntry {
        PulseMomentumEntry(date: Date(), momentum: "rising", recent: 9, prior: 5, hasGoal: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseMomentumEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseMomentumEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> PulseMomentumEntry {
        let d = PW.defaults
        return PulseMomentumEntry(
            date: Date(),
            momentum: d?.string(forKey: "widget_momentum") ?? "steady",
            recent: d?.integer(forKey: "widget_momentum_recent") ?? 0,
            prior: d?.integer(forKey: "widget_momentum_prior") ?? 0,
            hasGoal: d?.bool(forKey: "widget_has_goal") ?? false
        )
    }
}

struct PulseMomentumWidgetView: View {
    var entry: PulseMomentumEntry

    private var icon: String {
        switch entry.momentum {
        case "rising": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        default: return "arrow.right"
        }
    }
    private var tint: Color {
        switch entry.momentum {
        case "rising": return PW.green
        case "declining": return PW.accent
        default: return PW.gold
        }
    }
    private var label: String {
        switch entry.momentum {
        case "rising": return "RISING"
        case "declining": return "DECLINING"
        default: return "STEADY"
        }
    }
    private var deltaText: String {
        let delta = entry.recent - entry.prior
        if delta > 0 { return "+\(delta) vs last week" }
        if delta < 0 { return "\(delta) vs last week" }
        return "same as last week"
    }

    var body: some View {
        if !entry.hasGoal {
            PWEmpty(icon: "waveform.path.ecg", line: "No momentum yet", sub: "Start a goal in Pulse")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 13)).foregroundColor(tint)
                    Spacer()
                    Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(tint)
                }
                Spacer()
                Text("MOMENTUM")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                Text(label).font(.system(size: 22, weight: .bold)).foregroundColor(tint)
                Spacer()
                Text("\(entry.recent) pulses this week")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                Text(deltaText).font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(14)
        }
    }
}

struct PulseMomentumWidget: Widget {
    let kind = "PulseMomentumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseMomentumProvider()) { entry in
            PulseMomentumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Momentum")
        .description("Are you speeding up or slowing down?")
        .supportedFamilies([.systemSmall])
    }
}
