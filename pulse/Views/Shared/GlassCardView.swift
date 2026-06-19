import SwiftUI

// MARK: - Card View (Paper surface, subtle shadow)
// Replaces old glassmorphism with warm paper card.

struct GlassCardView<Content: View>: View {
    var accentColor: Color = PulseColors.signal
    var isInk: Bool = false
    let content: Content

    init(accentColor: Color = PulseColors.signal, isInk: Bool = false, @ViewBuilder content: () -> Content) {
        self.accentColor = accentColor
        self.isInk = isInk
        self.content = content()
    }

    var body: some View {
        content
            .padding(PulseSpacing.cardPadding)
            .background(isInk ? PulseColors.mono : PulseColors.paper)
            .foregroundColor(isInk ? PulseColors.onMono : PulseColors.ink)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Ink Card View (Always-dark "monitor" surface)
// Used for EKG goal cards, primary buttons, active states.

struct InkCardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(PulseSpacing.cardPadding)
            .background(PulseColors.mono)
            .foregroundColor(PulseColors.onMono)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
    }
}
