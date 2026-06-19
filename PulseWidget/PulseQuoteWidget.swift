import WidgetKit
import SwiftUI

// MARK: - Daily Spark (motivational quote) Widget

struct PulseQuoteEntry: TimelineEntry {
    let date: Date
    let quote: String
}

struct PulseQuoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseQuoteEntry {
        PulseQuoteEntry(date: Date(), quote: PulseWidgetQuotes.quote(for: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseQuoteEntry) -> Void) {
        completion(PulseQuoteEntry(date: Date(), quote: PulseWidgetQuotes.quote(for: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseQuoteEntry>) -> Void) {
        // One entry per 4-hour rotation window for the next 24h so the quote
        // changes on its own even while the app is closed.
        var entries: [PulseQuoteEntry] = []
        let now = Date()
        let window = 4.0 * 3600.0
        let bucketStart = (now.timeIntervalSince1970 / window).rounded(.down) * window
        for i in 0..<6 {
            let bucketTime = Date(timeIntervalSince1970: bucketStart + Double(i) * window)
            let showAt = i == 0 ? now : bucketTime
            entries.append(PulseQuoteEntry(date: showAt, quote: PulseWidgetQuotes.quote(for: bucketTime)))
        }
        let refresh = Date(timeIntervalSince1970: bucketStart + 6 * window)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct PulseQuoteWidgetView: View {
    var entry: PulseQuoteEntry
    @Environment(\.widgetFamily) var family

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: isLarge ? 18 : 14)).foregroundColor(PW.accent)
                Text("PULSE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PW.accent).tracking(2)
                Spacer()
            }
            Spacer(minLength: 0)
            Text(entry.quote)
                .font(.system(size: isLarge ? 22 : 16, weight: .semibold, design: .serif))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(isLarge ? 8 : 4)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("Today's spark").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(isLarge ? 20 : 16)
    }
}

struct PulseQuoteWidget: Widget {
    let kind = "PulseQuoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseQuoteProvider()) { entry in
            PulseQuoteWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Spark")
        .description("A fresh motivational line that changes through the day.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// Self-contained quote set + the same 4-hour rotation the app uses, so the
// widget refreshes on its own without the main app running.
enum PulseWidgetQuotes {
    static func quote(for now: Date) -> String {
        guard !all.isEmpty else { return "Start where you are. Use what you have. Do what you can." }
        let bucket = Int(now.timeIntervalSince1970 / (3600.0 * 4.0))
        let mixed = UInt64(bitPattern: Int64(bucket)) &* 6364136223846793005 &+ 1442695040888963407
        return all[Int(mixed % UInt64(all.count))]
    }

    static let all: [String] = [
        "Small daily improvements are how staggering results are built.",
        "You don't have to be extreme — just consistent.",
        "Discipline is choosing what you want most over what you want now.",
        "The work you avoid today is the work that waits for you tomorrow.",
        "Motivation gets you started. Habit keeps you going.",
        "A goal without a daily action is just a wish.",
        "Show up on the days you don't feel like it — that's where it's won.",
        "Progress, not perfection.",
        "One pulse at a time is how mountains get moved.",
        "The hardest rep is the one that builds you.",
        "Done beats perfect every single time.",
        "Today's effort is tomorrow's foundation.",
        "Consistency compounds. So does quitting.",
        "Start before you're ready — readiness comes from starting.",
        "Your future self is watching what you do right now.",
        "The streak protects the goal. Don't break the chain.",
        "What you repeat, you become.",
        "Hard now, easy later. Easy now, hard later.",
        "You won't always be motivated, so learn to be disciplined.",
        "Action cures fear.",
        "If it matters, do it daily.",
        "You rise to the level of your habits, not your hopes.",
        "Win the morning, win the day.",
        "Effort is the one variable entirely in your control.",
        "Every expert was once a beginner who refused to quit.",
        "Slow progress is still progress. Don't stop.",
        "Make it so small you can't say no.",
        "The dip is where most people quit. Push one more day.",
        "Don't count the days. Make the days count.",
        "Energy follows action, not the other way around.",
        "Discipline weighs ounces. Regret weighs tons.",
        "Be the kind of person who finishes.",
        "Focus on the next pulse, not the whole mountain.",
        "Repetition is the mother of mastery.",
        "Your habits are voting for who you'll become.",
        "Do the boring work brilliantly.",
        "Greatness is just consistency dressed in patience.",
        "If you're tired, learn to rest — not to quit.",
        "Stop waiting for perfect conditions. Begin in this one.",
        "What gets scheduled gets done.",
        "You don't find time. You make it.",
        "Aim for one percent better than yesterday.",
        "Momentum is built, not found.",
        "Quiet consistency beats loud ambition.",
        "Your only competition is who you were yesterday.",
        "Build the system and the results take care of themselves.",
        "When you feel like stopping, that's usually the moment that counts.",
        "Patience plus persistence is unstoppable.",
        "Make discipline your default, not your decision.",
        "Keep your promises to yourself first.",
        "The grind is quiet. The results are loud.",
        "Become addicted to the process and the outcome chases you.",
        "You can do hard things — you've done them before.",
        "Falling behind is recoverable. Quitting is not.",
        "Stack the days and the weeks take care of themselves.",
        "Your goals don't care how you feel — show up anyway.",
        "Trade instant comfort for lasting pride.",
        "Dreams written down with deadlines become plans.",
        "Habits are the compound interest of self-improvement.",
        "The work is the reward.",
        "Stay in the game long enough to get good.",
        "A goal is a promise to your future self — keep it.",
        "Cut the goal into pulses small enough to win.",
        "Show up tired. Show up unsure. Just show up.",
        "Begin again, as many times as it takes.",
        "Don't fear slow. Fear stopped.",
        "Build proof, not promises.",
        "Action is the antidote to anxiety.",
        "Make today a link in a long, unbroken chain.",
        "Be stubborn about the goal, flexible about the method.",
        "One honest hour beats ten distracted ones.",
        "You're closer than the doubt is telling you."
    ]
}
