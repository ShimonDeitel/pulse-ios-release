import AppIntents
import WidgetKit
import Foundation

/// Interactive AppIntent invoked when the user taps "Mark Done" on a widget.
/// Runs in the widget extension process — no app launch required.
/// Persists the completion via App Group UserDefaults; the main app picks it up
/// on next foreground and updates Core Data + fires the celebration.
@available(iOS 17.0, *)
struct CompletePulseIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete pulse"
    static var description = IntentDescription("Mark a pulse complete from the home screen.")

    // Run in the widget process so the home screen stays put.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Pulse ID")
    var pulseID: String

    @Parameter(title: "Goal ID")
    var goalID: String

    init() {}

    init(pulseID: String, goalID: String) {
        self.pulseID = pulseID
        self.goalID = goalID
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.shimondeitel.pulsegoals")

        // Queue the completion for the main app to sync into Core Data.
        var pending = defaults?.array(forKey: "pending_completions") as? [[String: String]] ?? []
        pending.append([
            "pulse_id": pulseID,
            "goal_id": goalID,
            "completed_at": ISO8601DateFormatter().string(from: Date())
        ])
        defaults?.set(pending, forKey: "pending_completions")

        // Optimistic widget update — show the next pulse right away.
        // Stored next-pulse data was written by WidgetDataService.
        if let nextNumber = defaults?.integer(forKey: "widget_pulse_after_next_number"),
           let nextTitle = defaults?.string(forKey: "widget_pulse_after_next_title"),
           let nextMinutes = defaults?.integer(forKey: "widget_pulse_after_next_minutes"),
           let nextID = defaults?.string(forKey: "widget_pulse_after_next_id") {
            defaults?.set(nextNumber, forKey: "widget_next_pulse_number")
            defaults?.set(nextTitle, forKey: "widget_next_pulse_title")
            defaults?.set(nextMinutes, forKey: "widget_next_pulse_minutes")
            defaults?.set(nextID, forKey: "widget_next_pulse_id")
        }

        // Bump completion counter + last-completed ID so the widget can flash
        // a brief "Just completed" success state on next render.
        let prevCount = defaults?.integer(forKey: "widget_completed_pulses") ?? 0
        defaults?.set(prevCount + 1, forKey: "widget_completed_pulses")
        defaults?.set(pulseID, forKey: "widget_last_completed_id")
        defaults?.set(Date().timeIntervalSince1970, forKey: "widget_last_completed_at")

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
