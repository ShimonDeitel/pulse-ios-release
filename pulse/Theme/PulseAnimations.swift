import SwiftUI

// MARK: - Pulse Animation System
// Philosophy: Subtle, fast transitions. Screen fade-in at 0.25s.
// Press feedback at scale(0.97). Message slide-ups at 0.32s.
// EKG trace drawing at 2.4s.

struct PulseAnimations {
    // ── Standard — All UI transitions ───────────────────────
    static let standard = Animation.easeOut(duration: 0.25)

    // ── Emphasized — Screen transitions, modal presentations ─
    static let emphasized = Animation.easeOut(duration: 0.35)

    // ── Quick — Micro-interactions, press feedback ──────────
    static let quick = Animation.easeOut(duration: 0.12)

    // ── Reveal — Numbers, progress, first-load animations ───
    static let reveal = Animation.easeOut(duration: 0.6)

    // ── Cinematic — Celebration, onboarding, achievement ────
    static let cinematic = Animation.easeOut(duration: 0.8)

    // ── Screen fade-in — 0.25s translateY(8px) -> 0 ────────
    static let screenFade = Animation.easeOut(duration: 0.25)

    // ── Message — Chat bubble slide-up ──────────────────────
    static let messageIn = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)

    // ── EKG trace drawing ───────────────────────────────────
    static let ekgDraw = Animation.easeOut(duration: 2.4)

    // ── Live pulse — breathing animation ────────────────────
    static let livePulse = Animation.easeOut(duration: 1.6).repeatForever(autoreverses: false)

    // ── Gentle spring — Cards, interactive elements ─────────
    static let gentle = Animation.spring(response: 0.4, dampingFraction: 0.9)

    // ── Press feedback constants ────────────────────────────
    static let pressScale: CGFloat = 0.97
    static let pressOpacity: Double = 0.85

    // ── Legacy aliases ──────────────────────────────────────
    static let smooth = emphasized
    static let expressive = cinematic
}

extension Animation {
    static var pulseSpring: Animation { PulseAnimations.gentle }
    static var pulseFast: Animation { PulseAnimations.quick }
    static var pulseSmooth: Animation { PulseAnimations.emphasized }
}
