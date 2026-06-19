import WidgetKit
import SwiftUI

// MARK: - Level & XP Widget

struct PulseLevelEntry: TimelineEntry {
    let date: Date
    let level: Int
    let totalXP: Int
    let xpForNext: Int
    let progress: Double
}

struct PulseLevelProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseLevelEntry {
        PulseLevelEntry(date: Date(), level: 5, totalXP: 540, xpForNext: 600, progress: 0.6)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseLevelEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseLevelEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> PulseLevelEntry {
        let d = PW.defaults
        return PulseLevelEntry(
            date: Date(),
            level: max(1, d?.integer(forKey: "widget_level") ?? 1),
            totalXP: d?.integer(forKey: "widget_total_xp") ?? 0,
            xpForNext: max(1, d?.integer(forKey: "widget_xp_for_next") ?? 200),
            progress: d?.double(forKey: "widget_xp_progress") ?? 0
        )
    }
}

struct PulseLevelWidgetView: View {
    var entry: PulseLevelEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 14)).foregroundColor(PW.gold)
                Spacer()
                Text("\(Int(entry.progress * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("LEVEL")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            Text("\(entry.level)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            PWBar(progress: entry.progress, tint: PW.gold)
            Text("\(entry.totalXP)/\(entry.xpForNext) XP")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(14)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 7)
                Circle().trim(from: 0, to: min(1, max(0, entry.progress)))
                    .stroke(PW.gold, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("LV").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                    Text("\(entry.level)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundColor(PW.gold)
                    Text("Level Progress")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                }
                Text("\(entry.totalXP) XP total")
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                Text("\(max(0, entry.xpForNext - entry.totalXP)) XP to Level \(entry.level + 1)")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                PWBar(progress: entry.progress, tint: PW.gold)
            }
        }
        .padding(16)
    }
}

struct PulseLevelWidget: Widget {
    let kind = "PulseLevelWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseLevelProvider()) { entry in
            PulseLevelWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Level & XP")
        .description("Your level and progress to the next one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
