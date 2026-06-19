import WidgetKit
import SwiftUI

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Progress & mission
        PulseProgressWidget()      // small, medium
        PulseMissionWidget()       // large hero
        // Streak & momentum
        PulseStreakWidget()        // small, medium
        PulseMomentumWidget()      // small
        // Level & deadline
        PulseLevelWidget()         // small, medium
        PulseDeadlineWidget()      // small, medium
        // Pulses (interactive)
        PulseNextPulseWidget()     // small, medium
        PulseTodayWidget()         // small, medium
        PulseQuickCompleteWidget() // small
        // Daily spark
        PulseQuoteWidget()         // medium, large
    }
}
