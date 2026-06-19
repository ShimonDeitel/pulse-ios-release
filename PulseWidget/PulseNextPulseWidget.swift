import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Next Pulse Widget (interactive — tap to complete)

struct PulseNextPulseEntry: TimelineEntry {
    let date: Date
    let pulseNumber: Int
    let pulseTitle: String
    let pulseID: String
    let estimatedMinutes: Int
    let goalTitle: String
    let goalID: String
    /// True if a completion just happened in the last 4 seconds — show success flash.
    let justCompleted: Bool
}

struct PulseNextPulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseNextPulseEntry {
        PulseNextPulseEntry(
            date: Date(),
            pulseNumber: 12,
            pulseTitle: "Set up your App Store Connect listing",
            pulseID: "preview",
            estimatedMinutes: 30,
            goalTitle: "Launch my app",
            goalID: "preview-goal",
            justCompleted: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseNextPulseEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseNextPulseEntry>) -> Void) {
        let now = Date()
        let entry = loadEntry()

        // If the user just completed a pulse, show the success flash for 3s
        // then automatically reload with the next pulse.
        if entry.justCompleted {
            let cleanEntry = PulseNextPulseEntry(
                date: now.addingTimeInterval(3),
                pulseNumber: entry.pulseNumber,
                pulseTitle: entry.pulseTitle,
                pulseID: entry.pulseID,
                estimatedMinutes: entry.estimatedMinutes,
                goalTitle: entry.goalTitle,
                goalID: entry.goalID,
                justCompleted: false
            )
            let timeline = Timeline(entries: [entry, cleanEntry],
                                    policy: .after(now.addingTimeInterval(60)))
            completion(timeline)
            return
        }

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> PulseNextPulseEntry {
        let defaults = UserDefaults(suiteName: "group.com.shimondeitel.pulsegoals")
        let lastCompletedAt = defaults?.double(forKey: "widget_last_completed_at") ?? 0
        let justCompleted = (Date().timeIntervalSince1970 - lastCompletedAt) < 3.0

        return PulseNextPulseEntry(
            date: Date(),
            pulseNumber: defaults?.integer(forKey: "widget_next_pulse_number") ?? 1,
            pulseTitle: defaults?.string(forKey: "widget_next_pulse_title") ?? "Complete your next pulse",
            pulseID: defaults?.string(forKey: "widget_next_pulse_id") ?? "",
            estimatedMinutes: defaults?.integer(forKey: "widget_next_pulse_minutes") ?? 15,
            goalTitle: defaults?.string(forKey: "widget_goal_title") ?? "No active goal",
            goalID: defaults?.string(forKey: "widget_goal_id") ?? "",
            justCompleted: justCompleted
        )
    }
}

struct PulseNextPulseWidgetView: View {
    var entry: PulseNextPulseEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.justCompleted {
            successFlashView
        } else {
            normalView
        }
    }

    // MARK: - Success flash (after tap)

    private var successFlashView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(hex: "91231C"))
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("PULSE COMPLETE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "91231C"))
                .tracking(1.2)
            Text("+10 XP")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }

    // MARK: - Normal pulse view

    private var normalView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("PULSE \(String(format: "%02d", entry.pulseNumber))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "91231C"))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("\(entry.estimatedMinutes)m")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }

            // Title
            Text(entry.pulseTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(family == .systemMedium ? 2 : 2)

            Spacer(minLength: 4)

            // Goal reference
            HStack(spacing: 4) {
                Image(systemName: "target")
                    .font(.system(size: 9))
                Text(entry.goalTitle)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)

            // Interactive Mark Done button (iOS 17+)
            if #available(iOS 17.0, *), !entry.pulseID.isEmpty {
                Button(intent: CompletePulseIntent(pulseID: entry.pulseID, goalID: entry.goalID)) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Mark Done")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(hex: "91231C"))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

struct PulseNextPulseWidget: Widget {
    let kind: String = "PulseNextPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseNextPulseProvider()) { entry in
            PulseNextPulseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Pulse")
        .description("Tap to mark today's pulse done — no need to open the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
