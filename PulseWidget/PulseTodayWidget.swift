import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Today's Pulses Widget (interactive — tap to complete the next one)

struct PulseTodayEntry: TimelineEntry {
    let date: Date
    let done: Int
    let total: Int
    let goalTitle: String
    let nextTitle: String
    let nextID: String
    let goalID: String
    let hasGoal: Bool
    let justCompleted: Bool
}

struct PulseTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseTodayEntry {
        PulseTodayEntry(date: Date(), done: 1, total: 3, goalTitle: "Launch my app",
                        nextTitle: "Write the landing page copy", nextID: "p", goalID: "g",
                        hasGoal: true, justCompleted: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseTodayEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseTodayEntry>) -> Void) {
        let e = load()
        if e.justCompleted {
            let clean = PulseTodayEntry(date: Date().addingTimeInterval(3), done: e.done, total: e.total,
                                        goalTitle: e.goalTitle, nextTitle: e.nextTitle, nextID: e.nextID,
                                        goalID: e.goalID, hasGoal: e.hasGoal, justCompleted: false)
            completion(Timeline(entries: [e, clean], policy: .after(Date().addingTimeInterval(60))))
            return
        }
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func load() -> PulseTodayEntry {
        let d = PW.defaults
        let last = d?.double(forKey: "widget_last_completed_at") ?? 0
        return PulseTodayEntry(
            date: Date(),
            done: d?.integer(forKey: "widget_today_done") ?? 0,
            total: d?.integer(forKey: "widget_today_total") ?? 0,
            goalTitle: d?.string(forKey: "widget_goal_title") ?? "No active goal",
            nextTitle: d?.string(forKey: "widget_next_pulse_title") ?? "All caught up",
            nextID: d?.string(forKey: "widget_next_pulse_id") ?? "",
            goalID: d?.string(forKey: "widget_goal_id") ?? "",
            hasGoal: d?.bool(forKey: "widget_has_goal") ?? false,
            justCompleted: (Date().timeIntervalSince1970 - last) < 3.0
        )
    }
}

struct PulseTodayWidgetView: View {
    var entry: PulseTodayEntry
    @Environment(\.widgetFamily) var family

    private var allDone: Bool { entry.total > 0 && entry.done >= entry.total }
    private var ratio: Double { entry.total > 0 ? Double(entry.done) / Double(entry.total) : 0 }

    var body: some View {
        if !entry.hasGoal {
            PWEmpty(icon: "checklist", line: "No pulses today", sub: "Start a goal in Pulse")
        } else if entry.justCompleted {
            flash
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var flash: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundColor(PW.accent)
            Text("NICE").font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(PW.accent).tracking(2)
            Text("\(entry.done)/\(entry.total) today")
                .font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
    }

    private var ringCount: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 6)
            Circle().trim(from: 0, to: ratio)
                .stroke(PW.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(entry.done)/\(entry.total)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(.primary)
                Text("TODAY").font(.system(size: 7, weight: .medium)).foregroundColor(.secondary)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist").font(.system(size: 13)).foregroundColor(PW.accent)
                Spacer()
                ringCount.frame(width: 46, height: 46)
            }
            Spacer()
            Text(allDone ? "All done today" : "Today's pulses")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
            if !allDone, !entry.nextID.isEmpty {
                completeButton("Mark Done")
            } else {
                Text(entry.goalTitle).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ringCount.frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(allDone ? "All pulses done" : "Next pulse")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(PW.accent)
                Text(allDone ? entry.goalTitle : entry.nextTitle)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
                Spacer(minLength: 2)
                if !allDone, !entry.nextID.isEmpty {
                    completeButton("Mark Done")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func completeButton(_ label: String) -> some View {
        Button(intent: CompletePulseIntent(pulseID: entry.nextID, goalID: entry.goalID)) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(PW.accent).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PulseTodayWidget: Widget {
    let kind = "PulseTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseTodayProvider()) { entry in
            PulseTodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Pulses")
        .description("See today's pulses and tap to complete the next one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
