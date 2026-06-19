import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Quick Complete Widget (one big tap-to-complete button)

struct PulseQuickEntry: TimelineEntry {
    let date: Date
    let pulseNumber: Int
    let pulseTitle: String
    let pulseID: String
    let goalID: String
    let hasGoal: Bool
    let justCompleted: Bool
}

struct PulseQuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseQuickEntry {
        PulseQuickEntry(date: Date(), pulseNumber: 7, pulseTitle: "Draft the outline",
                        pulseID: "p", goalID: "g", hasGoal: true, justCompleted: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseQuickEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseQuickEntry>) -> Void) {
        let e = load()
        if e.justCompleted {
            let clean = PulseQuickEntry(date: Date().addingTimeInterval(3), pulseNumber: e.pulseNumber,
                                        pulseTitle: e.pulseTitle, pulseID: e.pulseID, goalID: e.goalID,
                                        hasGoal: e.hasGoal, justCompleted: false)
            completion(Timeline(entries: [e, clean], policy: .after(Date().addingTimeInterval(60))))
            return
        }
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func load() -> PulseQuickEntry {
        let d = PW.defaults
        let last = d?.double(forKey: "widget_last_completed_at") ?? 0
        return PulseQuickEntry(
            date: Date(),
            pulseNumber: d?.integer(forKey: "widget_next_pulse_number") ?? 1,
            pulseTitle: d?.string(forKey: "widget_next_pulse_title") ?? "Complete your next pulse",
            pulseID: d?.string(forKey: "widget_next_pulse_id") ?? "",
            goalID: d?.string(forKey: "widget_goal_id") ?? "",
            hasGoal: d?.bool(forKey: "widget_has_goal") ?? false,
            justCompleted: (Date().timeIntervalSince1970 - last) < 3.0
        )
    }
}

struct PulseQuickWidgetView: View {
    var entry: PulseQuickEntry

    var body: some View {
        if !entry.hasGoal || entry.pulseID.isEmpty {
            PWEmpty(icon: "bolt.fill",
                    line: entry.hasGoal ? "All pulses done" : "No active goal",
                    sub: entry.hasGoal ? "Nice work today" : "Start one in Pulse")
        } else if entry.justCompleted {
            successView
        } else {
            normalView
        }
    }

    private var successView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(PW.accent).frame(width: 54, height: 54)
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundColor(.white)
            }
            Text("DONE").font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(PW.accent).tracking(2)
            Text("+10 XP").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
    }

    private var normalView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PULSE \(String(format: "%02d", entry.pulseNumber))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(PW.accent)
                Spacer()
                Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundColor(PW.accent)
            }
            Text(entry.pulseTitle)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary).lineLimit(3)
            Spacer(minLength: 2)
            Button(intent: CompletePulseIntent(pulseID: entry.pulseID, goalID: entry.goalID)) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold))
                    Text("Complete").font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(PW.accent).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
}

struct PulseQuickCompleteWidget: Widget {
    let kind = "PulseQuickCompleteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseQuickProvider()) { entry in
            PulseQuickWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Complete")
        .description("One tap to complete your next pulse — no app needed.")
        .supportedFamilies([.systemSmall])
    }
}
