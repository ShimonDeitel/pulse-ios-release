import SwiftUI

// MARK: - Pulse Design System Colors
// ────────────────────────────────────────────────────────────
// STRICT 5-COLOR PALETTE
//
//   1. Signal Red   #FF2D20  — the ONE accent color
//   2. Cream        #F4F1E8  — light background
//   3. Warm Dark    #0E0C08  — dark background
//   4. Mono Black   #0A0A0A  — always-dark cards, buttons
//   5. White        #FFFFFF  — text on dark, light elements
//
// All other tones are opacity/shade variants of these five.
// No orange, no purple, no pink, no green, no blue.
// ────────────────────────────────────────────────────────────

struct PulseColors {

    // ── Surface Ladder ──────────────────────────────────────
    // Light: warm cream/paper. Dark: warm near-black.

    /// App canvas — warm cream / deep warm black
    static let background = adaptive(light: "F4F1E8", dark: "0E0C08")
    /// Primary surface — cards, list rows
    static let surface = adaptive(light: "FDFBF4", dark: "181612")
    /// Elevated surface — modals, popovers
    static let surfaceElevated = adaptive(light: "FDFBF4", dark: "1E1C16")
    /// Container surface — inputs, wells
    static let surfaceContainer = adaptive(light: "EBE6D6", dark: "232019")
    /// Bright surface — hover states
    static let surfaceBright = adaptive(light: "FFFFFF", dark: "242018")

    // Semantic surface aliases
    static let cream = adaptive(light: "F4F1E8", dark: "0E0C08")
    static let cream2 = adaptive(light: "EBE6D6", dark: "1A1814")
    static let paper = adaptive(light: "FDFBF4", dark: "181612")
    static let ink = adaptive(light: "0A0A0A", dark: "F4F1E8")
    static let ink2 = adaptive(light: "1C1C1C", dark: "E8E3D2")
    // Brightened dark variants so secondary + tertiary text stay readable on
    // the warm-black background (the old dark muted2 was nearly invisible).
    static let muted = adaptive(light: "8A847A", dark: "A29C90")
    static let muted2 = adaptive(light: "C8C2B3", dark: "76705F")

    // Hairline separators
    static let hair = adaptive(light: "0A0A0A", dark: "F4F1E8").opacity(0.08)
    static let hairStrong = adaptive(light: "0A0A0A", dark: "F4F1E8").opacity(0.15)

    // ── Mono — The always-dark "monitor" surface ────────────
    // Stays dark in BOTH themes. Used for primary buttons,
    // active chips, chat bubbles.

    static let mono = Color(hex: "0A0A0A")
    static let mono2 = Color(hex: "1C1C1C")
    static let onMono = Color.white

    // ── Signal (Heartbeat Red) ──────────────────────────────
    // The ONE accent color. EKG traces, live dots, urgency,
    // CTAs, pulse indicators. Nothing else is vibrant.

    // Universal accent — single brand red shared across every CTA, ring,
    // pill, signal pulse, badge. Pulled to one constant so we can tune the
    // entire app's character from a single source of truth.
    // Light keeps the deep brand brick-red (#91231C). Dark uses a brighter
    // red so CTAs, rings, and pills are actually legible on the near-black
    // background instead of disappearing into it.
    static let signal = adaptive(light: "91231C", dark: "D24438")
    static let signalDim = adaptive(light: "91231C", dark: "D24438").opacity(0.35)

    // Second accent — the warm gold used for Pro/premium status (the yellow
    // verified checkmark). Pairs with signal red for paid/celebration states.
    static let gold = Color(hex: "C9A227")
    static let goldDim = Color(hex: "C9A227").opacity(0.35)

    // Natural completion green — a calm, REGULAR green (never neon). Used for
    // "done" / "marked complete" affirmations and good-form feedback. Brighter
    // in dark mode so it stays legible on the warm-black background.
    static let green = adaptive(light: "3F7A52", dark: "5FA873")

    // ── Primary — the interactive accent (signal red) ─────────
    static let primary = signal
    static let primaryContainer = adaptive(light: "2D1414", dark: "2D1414")
    static let onPrimary = Color.white
    static let onPrimaryContainer = Color(hex: "F4F1E8")
    static let primaryGlow = signal.opacity(0.35)

    // ── Semantic Colors — all mapped to signal or muted ─────
    // No green, no orange, no purple. Only red + neutral shades.

    static let success = signal              // completions use signal
    static let successContainer = adaptive(light: "FFEBE9", dark: "2D1414")
    static let warning = signal.opacity(0.7) // warnings = dimmed signal
    static let warningContainer = adaptive(light: "FFF0EE", dark: "2D1A14")
    static let danger = signal
    static let dangerContainer = adaptive(light: "FFE8E6", dark: "2D1414")

    // ── Removed Colors — mapped to FULL signal (no opacity!) ──
    // Previously these used signal.opacity(0.6) / 0.45 which rendered as
    // muddy purple-brown on cream backgrounds. Now they're full dark red.
    static let secondary = signal
    static let secondaryContainer = adaptive(light: "FFEBE9", dark: "2D1414")
    static let tertiary = signal
    static let tertiaryContainer = adaptive(light: "FFF0EE", dark: "2D1A14")
    static let pulse = signal
    static let pulseDim = signal.opacity(0.3)
    static let warn = signal

    // ── Text Hierarchy ──────────────────────────────────────
    // Ink in light mode, cream in dark mode. 3 tiers.

    static let textPrimary = ink
    static let textSecondary = muted
    static let textTertiary = muted2

    // ── Borders ─────────────────────────────────────────────
    static let outline = hair
    static let outlineVariant = adaptive(light: "0A0A0A", dark: "F4F1E8").opacity(0.10)

    // ── Tab Bar ─────────────────────────────────────────────
    static let tabBarBg = adaptive(light: "F4F1E8", dark: "0E0C08").opacity(0.92)

    // ── Gradients — only signal-based ───────────────────────
    static let gradientPrimary = LinearGradient(
        colors: [signal, signal.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let gradientSubtle = LinearGradient(
        colors: [signal.opacity(0.08), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )
    static let gradientHot = LinearGradient(
        colors: [signal, signal.opacity(0.6)],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let gradientCool = LinearGradient(
        colors: [signal.opacity(0.5), signal.opacity(0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let gradientNeon = LinearGradient(
        colors: [signal, signal.opacity(0.5)],
        startPoint: .leading,
        endPoint: .trailing
    )

    // ── Category Colors — all full signal red ───────────────
    // Categories differentiate by icon, not by color.
    // Full signal red so icons look crisp dark-red, not muddy purple.
    static let categoryHealth = signal
    static let categoryCareer = signal
    static let categoryFinance = signal
    static let categoryLearning = signal
    static let categoryFitness = signal
    static let categoryCreative = signal

    // ── Medal Colors — warm neutrals ────────────────────────
    static let medalGold = Color(hex: "C8B88A")   // warm muted gold
    static let medalSilver = Color(hex: "A0A0A0")
    static let medalBronze = Color(hex: "8A7260")

    // ── Accent Colors — only signal red ─────────────────────
    static let accentRed = signal
    static let accentOrange = signal     // remapped from orange
    static let accentGreen = signal      // remapped from green
    static let accentBlue = signal       // remapped from blue
    static let accentLime = signal       // remapped from lime
    static let accentPurple = signal     // remapped from purple

    // ── Legacy Alias ────────────────────────────────────────
    static let accent = signal

    // ── Helpers ──────────────────────────────────────────────
    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
