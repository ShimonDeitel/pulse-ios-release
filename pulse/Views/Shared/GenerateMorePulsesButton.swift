import SwiftUI
import CoreData

/// Universal "Generate More Pulses" button for any goal detail page.
///
/// Tap → AI appends ~7 fresh pulses to the goal that build on what's already
/// been done. Existing pulses (done or pending) are untouched. Shows loading
/// state inline; surfaces success / failure via a brief banner.
struct GenerateMorePulsesButton: View {
    let goal: Goal
    var howMany: Int = 7

    @State private var isGenerating = false
    @State private var lastResult: Result? = nil
    @State private var showingUpgrade = false

    enum Result: Equatable {
        case added(Int)
        case failed
    }

    var body: some View {
        if !SubscriptionManager.shared.hasAIGeneration {
            // Free has NO AI. They add their own pulses via the ⋯ → "Add a
            // step" menu; this surfaces the Pro upsell for AI generation.
            Button { showingUpgrade = true; PulseHaptics.light() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold))
                    Text("Generate pulses with AI — Pro")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(PulseColors.gold)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(PulseColors.gold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PulseColors.gold.opacity(0.35), lineWidth: 1)
                )
            }
            .sheet(isPresented: $showingUpgrade) { UpgradeView() }
        } else {
            proButton
        }
    }

    private var proButton: some View {
        VStack(spacing: 8) {
            Button {
                generate()
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView().tint(PulseColors.signal).scaleEffect(0.85)
                        Text("Generating more pulses…")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Generate More Pulses")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(PulseColors.signal)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(PulseColors.signal.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PulseColors.signal.opacity(0.35), lineWidth: 1)
                )
            }
            .disabled(isGenerating)

            if let r = lastResult {
                switch r {
                case .added(let n):
                    Label("Added \(n) new pulses — scroll down to see them.",
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PulseColors.signal)
                        .transition(.opacity)
                case .failed:
                    Label("Couldn't add pulses — try again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PulseColors.muted)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lastResult)
        .animation(.easeInOut(duration: 0.2), value: isGenerating)
    }

    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        lastResult = nil
        PulseHaptics.medium()
        let objectID = goal.objectID
        Task {
            let count = await AIPulseGenerator.shared.appendMorePulses(
                forGoalWithID: objectID,
                howMany: howMany
            )
            await MainActor.run {
                isGenerating = false
                lastResult = (count > 0) ? .added(count) : .failed
                if count > 0 { PulseHaptics.success() }
            }
            // Auto-clear the banner after 6 seconds.
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run { lastResult = nil }
        }
    }
}
