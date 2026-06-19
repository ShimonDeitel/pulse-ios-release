import SwiftUI
import UIKit

// MARK: - Pulse Typography System
// Philosophy: Geist-inspired — SF Pro with tight negative tracking for
// display text. SF Mono for data, stats, eyebrow labels.
// Large bold display moments. Monospace everywhere data lives.

struct PulseTypography {
    // Scales a base point size against the user's Dynamic Type setting using the
    // metrics of the supplied text style, while preserving the exact weight and
    // design of the original token. Computed (not cached) so values re-evaluate
    // when the content size category changes.
    private static func scaled(
        _ size: CGFloat,
        _ weight: Font.Weight,
        _ style: UIFont.TextStyle,
        design: Font.Design = .default
    ) -> Font {
        Font.system(
            size: UIFontMetrics(forTextStyle: style).scaledValue(for: size),
            weight: weight,
            design: design
        )
    }

    // ── Display — Hero numbers, key metrics ─────────────────
    // Weight 600, tight negative tracking (-0.04em). One per screen max.
    static var displayLarge: Font { scaled(56, .semibold, .largeTitle) }
    static var displayMedium: Font { scaled(44, .semibold, .largeTitle) }
    static var displaySmall: Font { scaled(36, .semibold, .largeTitle) }

    // ── Headline — Screen titles ────────────────────────────
    // h-1: 38px, h-2: 22px, h-3: 17px — all weight 600, tight tracking
    static var headlineLarge: Font { scaled(38, .semibold, .largeTitle) }
    static var headlineLargeEmphasized: Font { scaled(38, .bold, .largeTitle) }
    static var headlineMedium: Font { scaled(22, .semibold, .title2) }
    static var headlineSmall: Font { scaled(17, .semibold, .headline) }

    // ── Title — Card titles, list items ─────────────────────
    static var titleLarge: Font { scaled(22, .medium, .title2) }
    static var titleMedium: Font { scaled(15, .medium, .subheadline) }
    static var titleSmall: Font { scaled(14, .medium, .subheadline) }

    // ── Body — Descriptions, paragraphs ─────────────────────
    static var bodyLarge: Font { scaled(16, .regular, .body) }
    static var bodyMedium: Font { scaled(15, .regular, .body) }
    static var bodySmall: Font { scaled(13, .regular, .footnote) }

    // ── Label — Buttons, chips, metadata ────────────────────
    static var labelLarge: Font { scaled(15.5, .medium, .subheadline) }
    static var labelLargeEmphasized: Font { scaled(15.5, .semibold, .subheadline) }
    static var labelMedium: Font { scaled(13, .medium, .footnote) }
    static var labelSmall: Font { scaled(11, .medium, .caption2) }

    // ── Mono — Stats, timers, data-grade numbers ────────────
    // SF Mono. Tabular figures for column alignment.
    static var monoLarge: Font { scaled(48, .light, .largeTitle, design: .monospaced) }
    static var monoMedium: Font { scaled(32, .light, .title1, design: .monospaced) }
    static var monoSmall: Font { scaled(20, .regular, .title3, design: .monospaced) }
    static var monoCaption: Font { scaled(11, .medium, .caption2, design: .monospaced) }
    static var monoTag: Font { scaled(10.5, .medium, .caption2, design: .monospaced) }

    // ── Eyebrow — Category labels, uppercase mono ───────────
    // Monospaced, uppercase, wide letter-spacing. "t-eyebrow" in the reference.
    static var eyebrow: Font { scaled(10.5, .medium, .caption2, design: .monospaced) }
}

// MARK: - Tracking Modifier
// Display: -0.04em, headline: -0.025em, eyebrow: +0.14em

struct TrackingModifier: ViewModifier {
    let tracking: CGFloat
    func body(content: Content) -> some View {
        content.tracking(tracking)
    }
}

extension View {
    /// Display text: -0.04em (tight, impactful)
    func displayTracking() -> some View {
        modifier(TrackingModifier(tracking: -1.6))
    }

    /// Headline text: -0.025em
    func headlineTracking() -> some View {
        modifier(TrackingModifier(tracking: -0.6))
    }

    /// Body text: -0.01em (subtle tightening)
    func bodyTracking() -> some View {
        modifier(TrackingModifier(tracking: -0.15))
    }

    /// Eyebrow text: +0.14em (wide, uppercase mono)
    func eyebrowTracking() -> some View {
        modifier(TrackingModifier(tracking: 1.8))
    }

    /// Mono tracking: -0.02em
    func monoTracking() -> some View {
        modifier(TrackingModifier(tracking: -0.3))
    }
}
