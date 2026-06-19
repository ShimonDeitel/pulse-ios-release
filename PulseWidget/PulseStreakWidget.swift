import WidgetKit
import SwiftUI

// MARK: - Streak Widget

struct PulseStreakEntry: TimelineEntry {
    let date: Date
    let currentStreak: Int
    let longestStreak: Int
    let todayComplete: Bool
}

struct PulseStreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseStreakEntry {
        PulseStreakEntry(date: Date(), currentStreak: 7, longestStreak: 14, todayComplete: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseStreakEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseStreakEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> PulseStreakEntry {
        let defaults = UserDefaults(suiteName: "group.com.shimondeitel.pulsegoals")
        return PulseStreakEntry(
            date: Date(),
            currentStreak: defaults?.integer(forKey: "widget_streak") ?? 0,
            longestStreak: defaults?.integer(forKey: "widget_longest_streak") ?? 0,
            todayComplete: defaults?.bool(forKey: "widget_today_complete") ?? false
        )
    }
}

struct PulseStreakWidgetView: View {
    var entry: PulseStreakEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "91231C"))
                Spacer()
                if entry.todayComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "91231C"))
                }
            }

            VStack(spacing: 2) {
                Text("\(entry.currentStreak)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("DAY STREAK")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Text("Best: \(entry.longestStreak)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.todayComplete ? "DONE" : "PENDING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(entry.todayComplete ? Color(hex: "91231C") : .secondary)
            }
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            // Big flame + count
            ZStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color(hex: "91231C").opacity(0.14))
                VStack(spacing: 0) {
                    Text("\(entry.currentStreak)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("DAYS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 96)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 13)).foregroundColor(Color(hex: "91231C"))
                    Text("Current Streak").font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                }
                Text("Personal best: \(entry.longestStreak) days")
                    .font(.system(size: 12)).foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: entry.todayComplete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(entry.todayComplete ? Color(hex: "91231C") : .secondary)
                    Text(entry.todayComplete ? "Today is locked in" : "Complete a pulse today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(entry.todayComplete ? .primary : .secondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

struct PulseStreakWidget: Widget {
    let kind: String = "PulseStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseStreakProvider()) { entry in
            PulseStreakWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Keep your streak alive. Don't break the chain.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
