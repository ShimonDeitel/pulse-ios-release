import SwiftUI

// MARK: - Shape Tokens
// Reference: --r-card: 22px, --r-lg: 28px, --r-pill: 999px

struct M3Shapes {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 22      // card radius
    static let extraLarge: CGFloat = 28  // large radius
    static let full: CGFloat = 9999     // pill
}

// MARK: - Elevation (Shadow Steps)
// Reference: --shadow-sm, --shadow-md, --shadow-lg

struct M3Elevation {
    static let level0: CGFloat = 0
    static let level1: CGFloat = 1
    static let level2: CGFloat = 2
    static let level3: CGFloat = 3
    static let level4: CGFloat = 4
    static let level5: CGFloat = 5
}

// MARK: - Card Modifier
// Warm paper background, subtle shadow, 22px radius.

struct M3Card: ViewModifier {
    var elevation: CGFloat = M3Elevation.level1
    var isInk: Bool = false

    func body(content: Content) -> some View {
        content
            .background(isInk ? PulseColors.mono : PulseColors.paper)
            .foregroundColor(isInk ? PulseColors.onMono : PulseColors.ink)
            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var shadowColor: Color {
        switch elevation {
        case 0: Color.clear
        case 1: Color.black.opacity(0.04)
        case 2: Color.black.opacity(0.06)
        default: Color.black.opacity(0.08)
        }
    }
    private var shadowRadius: CGFloat {
        switch elevation {
        case 0: 0
        case 1: 4
        case 2: 14
        default: 30
        }
    }
    private var shadowY: CGFloat {
        switch elevation {
        case 0: 0
        case 1: 1
        case 2: 5
        default: 15
        }
    }
}

// MARK: - Primary Button (Pill, Dark Mono Fill)
// Always dark background, white text. "btn-primary" in reference.

struct M3FilledButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseTypography.labelLargeEmphasized)
            .foregroundColor(PulseColors.onMono)
            .padding(.horizontal, PulseSpacing.buttonPaddingH)
            .padding(.vertical, PulseSpacing.buttonPaddingV)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PulseSpacing.buttonHeight)
            .background(PulseColors.mono)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? PulseAnimations.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? PulseAnimations.pressScale : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}

// MARK: - Signal Button (Pill, Red Fill)
// "btn-signal" in reference. For urgent/critical actions.

struct M3SignalButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseTypography.labelLargeEmphasized)
            .foregroundColor(.white)
            .padding(.horizontal, PulseSpacing.buttonPaddingH)
            .padding(.vertical, PulseSpacing.buttonPaddingV)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PulseSpacing.buttonHeight)
            .background(PulseColors.signal)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? PulseAnimations.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? PulseAnimations.pressScale : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}

// MARK: - Ghost Button (Transparent)
// "btn-ghost" in reference. Text-colored, no background.

struct M3GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseTypography.labelLargeEmphasized)
            .foregroundColor(PulseColors.ink)
            .padding(.horizontal, PulseSpacing.buttonPaddingH)
            .padding(.vertical, PulseSpacing.buttonPaddingV)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PulseSpacing.buttonHeight)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}

// MARK: - Outlined Button (Dashed Border)
// For "New goal" style actions — dashed ink border, no fill.

struct M3OutlinedButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseTypography.labelLargeEmphasized)
            .foregroundColor(PulseColors.ink)
            .padding(.horizontal, PulseSpacing.buttonPaddingH)
            .padding(.vertical, PulseSpacing.buttonPaddingV)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PulseSpacing.buttonHeight)
            .overlay(
                Capsule()
                    .strokeBorder(PulseColors.ink, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? PulseAnimations.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? PulseAnimations.pressScale : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}

// MARK: - Tonal Button (Legacy Compat)

struct M3TonalButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseTypography.labelLargeEmphasized)
            .foregroundColor(PulseColors.ink)
            .padding(.horizontal, PulseSpacing.buttonPaddingH)
            .padding(.vertical, PulseSpacing.buttonPaddingV)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PulseSpacing.buttonHeight)
            .background(PulseColors.cream2)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? PulseAnimations.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? PulseAnimations.pressScale : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}

// MARK: - Text Button (Minimal)

struct M3TextButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseTypography.labelLarge)
            .foregroundColor(PulseColors.ink)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(PulseAnimations.quick, value: configuration.isPressed)
    }
}

// MARK: - Chip Styles
// "chip" in reference: pill, mono font, uppercase, small.

struct PulseChip: View {
    let label: String
    var style: ChipStyle = .default

    enum ChipStyle {
        case `default`, ink, signal, pulse, outline
    }

    var body: some View {
        Text(label.uppercased())
            .font(PulseTypography.monoTag)
            .eyebrowTracking()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(chipBackground)
            .foregroundColor(chipForeground)
            .clipShape(Capsule())
            .overlay(
                style == .outline
                    ? Capsule().stroke(PulseColors.hairStrong, lineWidth: 1)
                    : nil
            )
    }

    private var chipBackground: Color {
        switch style {
        case .default: return PulseColors.cream2
        case .ink: return PulseColors.mono
        case .signal: return PulseColors.signal
        case .pulse: return PulseColors.pulse
        case .outline: return .clear
        }
    }

    private var chipForeground: Color {
        switch style {
        case .default: return PulseColors.ink
        case .ink, .signal, .pulse: return .white
        case .outline: return PulseColors.ink
        }
    }
}

// MARK: - Top status-bar fade
//
// A subtle frosted fade pinned under the iOS status bar so scrolled content
// never collides with the clock / signal indicators. The system UI reads
// cleanly above the fade.
struct TopScrollFade: View {
    var body: some View {
        GeometryReader { geo in
            // Transparent blur only — no gray bar. A frosted band that covers the
            // status bar AND extends ~40pt past it, held at low opacity so it reads
            // as a light blur (not a color wash). Being this tall, it forms a clear
            // separation zone between the iOS status bar (clock/battery) and the
            // app's title beneath it. The mask keeps the blur full through the top,
            // then fades it out over the lower third into the content.
            Rectangle().fill(.ultraThinMaterial)
            .frame(height: geo.safeAreaInsets.top + 40)
            .opacity(0.6)
            .mask(
                LinearGradient(
                    colors: [.black, .black, .black.opacity(0.45), .black.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - View Extensions

extension View {
    func m3Card(elevation: CGFloat = M3Elevation.level1) -> some View {
        modifier(M3Card(elevation: elevation))
    }

    func inkCard(elevation: CGFloat = M3Elevation.level1) -> some View {
        modifier(M3Card(elevation: elevation, isInk: true))
    }

    func pulseScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PulseColors.cream.ignoresSafeArea())
            .overlay(alignment: .top) { TopScrollFade() }
            .dismissesKeyboard()
    }

    func glassBackground(opacity: Double = 0.06) -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.3))
            .background(PulseColors.cream.opacity(opacity))
    }

    func neonGlow(_ color: Color, radius: CGFloat = 10) -> some View {
        self.shadow(color: color.opacity(0.3), radius: radius)
    }
}

// MARK: - Legacy Aliases

typealias PrimaryButtonStyle = M3FilledButton
typealias SecondaryButtonStyle = M3TonalButton
