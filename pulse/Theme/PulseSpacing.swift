import SwiftUI

// MARK: - Pulse Spacing System
// Matches the reference design: 22px screen edges, 18px card padding,
// 22px card radius, pill buttons.

struct PulseSpacing {
    // ── Micro — Internal component spacing ──────────────────
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8

    // ── Standard — Card padding, gaps, insets ───────────────
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20

    // ── Generous — Section padding, card internals ──────────
    static let xxl: CGFloat = 22     // screen edge inset (from reference)
    static let xxxl: CGFloat = 28

    // ── Section — Between major content blocks ──────────────
    static let section: CGFloat = 28
    static let sectionLarge: CGFloat = 48

    // ── Screen — Page-level edge insets ─────────────────────
    static let screenEdge: CGFloat = 22   // reference uses 22px
    static let screenBottom: CGFloat = 100 // space for tab bar

    // ── Card internals ──────────────────────────────────────
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 22    // --r-card: 22px
    static let cardRadiusLg: CGFloat = 28  // --r-lg: 28px
    static let cardGap: CGFloat = 14

    // ── Button ──────────────────────────────────────────────
    static let buttonHeight: CGFloat = 52
    static let buttonHeightCompact: CGFloat = 40
    static let buttonPaddingH: CGFloat = 22
    static let buttonPaddingV: CGFloat = 16
    static let buttonRadius: CGFloat = 9999  // --r-pill: 999px
}
