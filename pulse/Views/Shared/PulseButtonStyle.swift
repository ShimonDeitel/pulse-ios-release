import SwiftUI

// MARK: - Pulse Button Styles
// Reference: btn-primary (dark mono), btn-ghost (transparent),
// btn-signal (red), btn-block (full width)

enum PulseButtonVariant {
    case filled, signal, ghost, outlined, tonal, text
}

struct PulseButton: View {
    let title: String
    let variant: PulseButtonVariant
    let icon: String?
    let action: () -> Void

    init(_ title: String, variant: PulseButtonVariant = .filled, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: PulseSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
        }
        .buttonStyle(buttonStyleForVariant)
    }

    private var buttonStyleForVariant: some ButtonStyle {
        switch variant {
        case .filled: return AnyButtonStyle(M3FilledButton())
        case .signal: return AnyButtonStyle(M3SignalButton())
        case .ghost: return AnyButtonStyle(M3GhostButton())
        case .tonal: return AnyButtonStyle(M3TonalButton())
        case .outlined: return AnyButtonStyle(M3OutlinedButton())
        case .text: return AnyButtonStyle(M3TextButton())
        }
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
