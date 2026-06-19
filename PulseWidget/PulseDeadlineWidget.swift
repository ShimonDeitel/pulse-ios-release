import WidgetKit
import SwiftUI

// MARK: - Deadline Countdown Widget

struct PulseDeadlineEntry: TimelineEntry {
    let date: Date
    let deadline: Date?
    let start: Date?
    let goalTitle: String
    let hasGoal: Bool
}

struct PulseDeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseDeadlineEntry {
        PulseDeadlineEntry(date: Date(),
                           deadline: Date().addingTimeInterval(14 * 86_400),
                           start: Date().addingTimeInterval(-7 * 86_400),
                           goalTitle: "Launch my app", hasGoal: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseDeadlineEntry) -> Void) {
        completion(load(Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseDeadlineEntry>) -> Void) {
        // One entry per hour for the next 6h so the countdown stays current.
        var entries: [PulseDeadlineEntry] = []
        for h in 0..<6 {
            let d = Calendar.current.date(byAdding: .hour, value: h, to: Date()) ?? Date()
            entries.append(load(d))
        }
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func load(_ date: Date) -> PulseDeadlineEntry {
        let dd = PW.defaults
        let dts = dd?.double(forKey: "widget_deadline_ts") ?? 0
        let sts = dd?.double(forKey: "widget_goal_start_ts") ?? 0
        return PulseDeadlineEntry(
            date: date,
            deadline: dts > 0 ? Date(timeIntervalSince1970: dts) : nil,
            start: sts > 0 ? Date(timeIntervalSince1970: sts) : nil,
            goalTitle: dd?.string(forKey: "widget_goal_title") ?? "No active goal",
            hasGoal: dd?.bool(forKey: "widget_has_goal") ?? false
        )
    }
}

struct PulseDeadlineWidgetView: View {
    var entry: PulseDeadlineEntry
    @Environment(\.widgetFamily) var family

    private var secondsLeft: TimeInterval {
        guard let dl = entry.deadline else { return 0 }
        return max(0, dl.timeIntervalSince(entry.date))
    }
    private var days: Int { Int(secondsLeft / 86_400) }
    private var hours: Int { Int(secondsLeft.truncatingRemainder(dividingBy: 86_400) / 3600) }
    private var tint: Color { days < 7 ? PW.accent : (days < 30 ? PW.gold : PW.green) }
    private var elapsed: Double {
        guard let s = entry.start, let e = entry.deadline, e > s else { return 0 }
        return min(1, max(0, entry.date.timeIntervalSince(s) / e.timeIntervalSince(s)))
    }

    var body: some View {
        if !entry.hasGoal || entry.deadline == nil {
            PWEmpty(icon: "clock", line: "No deadline", sub: "Set one in Pulse")
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock.fill").font(.system(size: 13)).foregroundColor(tint)
                Spacer()
                Text("\(hours)h").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(days)").font(.system(size: 42, weight: .bold, design: .rounded)).foregroundColor(tint)
            Text(days == 1 ? "DAY LEFT" : "DAYS LEFT")
                .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
            Spacer()
            Text(entry.goalTitle).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(14)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.system(size: 12)).foregroundColor(tint)
                Text(entry.goalTitle).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(days)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(tint)
                Text("days").font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
                Text("\(hours)h").font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                Spacer()
                if let dl = entry.deadline {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("DUE").font(.system(size: 8, weight: .medium)).foregroundColor(.secondary)
                        Text(dl, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
                    }
                }
            }
            PWBar(progress: elapsed, tint: tint)
            Text("\(Int(elapsed * 100))% of your timeline elapsed")
                .font(.system(size: 10)).foregroundColor(.secondary)
        }
        .padding(16)
    }
}

struct PulseDeadlineWidget: Widget {
    let kind = "PulseDeadlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseDeadlineProvider()) { entry in
            PulseDeadlineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Deadline")
        .description("Days left until your goal deadline.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
