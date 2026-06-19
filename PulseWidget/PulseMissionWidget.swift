import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Mission Control Widget (large hero — everything at a glance)

struct PulseMissionEntry: TimelineEntry {
    let date: Date
    let goalTitle: String
    let completed: Int
    let total: Int
    let daysRemaining: Int
    let probability: Int
    let streak: Int
    let level: Int
    let xpProgress: Double
    let nextNumber: Int
    let nextTitle: String
    let nextID: String
    let goalID: String
    let hasGoal: Bool
    let justCompleted: Bool
}

struct PulseMissionProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseMissionEntry {
        PulseMissionEntry(date: Date(), goalTitle: "Launch my app", completed: 15, total: 30,
                          daysRemaining: 14, probability: 72, streak: 7, level: 5, xpProgress: 0.6,
                          nextNumber: 16, nextTitle: "Set up your App Store Connect listing",
                          nextID: "p", goalID: "g", hasGoal: true, justCompleted: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseMissionEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseMissionEntry>) -> Void) {
        let e = load()
        if e.justCompleted {
            let clean = makeEntry(from: e, date: Date().addingTimeInterval(3), justCompleted: false)
            completion(Timeline(entries: [e, clean], policy: .after(Date().addingTimeInterval(60))))
            return
        }
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func makeEntry(from e: PulseMissionEntry, date: Date, justCompleted: Bool) -> PulseMissionEntry {
        PulseMissionEntry(date: date, goalTitle: e.goalTitle, completed: e.completed, total: e.total,
                          daysRemaining: e.daysRemaining, probability: e.probability, streak: e.streak,
                          level: e.level, xpProgress: e.xpProgress, nextNumber: e.nextNumber,
                          nextTitle: e.nextTitle, nextID: e.nextID, goalID: e.goalID,
                          hasGoal: e.hasGoal, justCompleted: justCompleted)
    }

    private func load() -> PulseMissionEntry {
        let d = PW.defaults
        let last = d?.double(forKey: "widget_last_completed_at") ?? 0
        return PulseMissionEntry(
            date: Date(),
            goalTitle: d?.string(forKey: "widget_goal_title") ?? "No active goal",
            completed: d?.integer(forKey: "widget_completed_pulses") ?? 0,
            total: max(0, d?.integer(forKey: "widget_total_pulses") ?? 0),
            daysRemaining: d?.integer(forKey: "widget_days_remaining") ?? 0,
            probability: d?.integer(forKey: "widget_probability") ?? 0,
            streak: d?.integer(forKey: "widget_streak") ?? 0,
            level: max(1, d?.integer(forKey: "widget_level") ?? 1),
            xpProgress: d?.double(forKey: "widget_xp_progress") ?? 0,
            nextNumber: d?.integer(forKey: "widget_next_pulse_number") ?? 1,
            nextTitle: d?.string(forKey: "widget_next_pulse_title") ?? "All caught up",
            nextID: d?.string(forKey: "widget_next_pulse_id") ?? "",
            goalID: d?.string(forKey: "widget_goal_id") ?? "",
            hasGoal: d?.bool(forKey: "widget_has_goal") ?? false,
            justCompleted: (Date().timeIntervalSince1970 - last) < 3.0
        )
    }
}

struct PulseMissionWidgetView: View {
    var entry: PulseMissionEntry

    private var progress: Double { entry.total > 0 ? Double(entry.completed) / Double(entry.total) : 0 }
    private var allDone: Bool { entry.total > 0 && entry.completed >= entry.total }
    private var deadlineTint: Color {
        entry.daysRemaining < 7 ? PW.accent : (entry.daysRemaining < 30 ? PW.gold : PW.green)
    }

    var body: some View {
        if !entry.hasGoal {
            PWEmpty(icon: "scope", line: "No active mission", sub: "Open Pulse to start a goal")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MISSION CONTROL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PW.accent).tracking(1.5)
                    Text(entry.goalTitle)
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.primary).lineLimit(1)
                }
                Spacer()
                if entry.probability > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile").font(.system(size: 10))
                        Text("\(entry.probability)%").font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(PW.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(PW.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Middle: ring + stat chips
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    Circle().trim(from: 0, to: progress)
                        .stroke(PW.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.primary)
                        Text("\(entry.completed)/\(entry.total)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    statRow(icon: "flame.fill", tint: PW.accent,
                            value: "\(entry.streak)", label: entry.streak == 1 ? "day streak" : "day streak")
                    statRow(icon: "star.fill", tint: PW.gold,
                            value: "Lv \(entry.level)", label: "\(Int(entry.xpProgress * 100))% to next")
                    statRow(icon: "clock.fill", tint: deadlineTint,
                            value: "\(entry.daysRemaining)d", label: "remaining")
                }
                Spacer(minLength: 0)
            }

            Divider().opacity(0.4)

            // Bottom: next pulse + complete button
            if allDone {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 16)).foregroundColor(PW.green)
                    Text("Every pulse complete — outstanding.")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
                    Spacer()
                }
            } else if entry.justCompleted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundColor(PW.accent)
                    Text("Pulse complete · +10 XP")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(PW.accent)
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT · PULSE \(String(format: "%02d", entry.nextNumber))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.secondary)
                        Text(entry.nextTitle)
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if !entry.nextID.isEmpty {
                        Button(intent: CompletePulseIntent(pulseID: entry.nextID, goalID: entry.goalID)) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(PW.accent).clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(18)
    }

    private func statRow(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(tint).frame(width: 18)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.primary)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

struct PulseMissionWidget: Widget {
    let kind = "PulseMissionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseMissionProvider()) { entry in
            PulseMissionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mission Control")
        .description("Your whole mission at a glance — progress, streak, level, deadline and next pulse.")
        .supportedFamilies([.systemLarge])
    }
}
