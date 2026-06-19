import SwiftUI
import UIKit

extension UIApplication {
    /// Resign first responder anywhere in the app — closes any open keyboard.
    func endEditingEverywhere() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Installs ONE window-level tap recognizer so a tap anywhere off the keyboard
/// dismisses it — on EVERY screen, regardless of whether that screen uses
/// `pulseScreen()` or any SwiftUI gesture. This is far more reliable than
/// per-view SwiftUI gestures (which several screens were missing). The
/// recognizer:
///   • `cancelsTouchesInView = false` → taps still reach buttons / lists / scroll.
///   • ignores touches that land on a `UIControl` or text-input view, so it
///     never interferes with the field you are actually typing in.
///   • recognizes simultaneously with every other gesture → scrolling, drags,
///     and taps on controls all keep working.
final class KeyboardDismissInstaller: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissInstaller()
    private let recognizers = NSHashTable<UITapGestureRecognizer>.weakObjects()

    /// Attach the recognizer to every foreground window that doesn't have one
    /// yet. Safe to call repeatedly (on launch and every foreground).
    func installInAllWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                let already = window.gestureRecognizers?.contains {
                    ($0 as? UITapGestureRecognizer)?.name == "pulse.kbd-dismiss"
                } ?? false
                guard !already else { continue }
                let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
                tap.name = "pulse.kbd-dismiss"
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
                recognizers.add(tap)
            }
        }
    }

    @objc private func handleTap() {
        UIApplication.shared.endEditingEverywhere()
    }

    // Coexist with every other gesture (buttons, scrolling, drags, etc.).
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // Don't even fire when the tap lands on a control or a text input — those
    // taps must behave normally (focus a field, hit a button).
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let v = touch.view else { return true }
        if v is UIControl { return false }
        if v is UITextField || v is UITextView { return false }
        // Walk up a few superviews in case the hit view is inside a control.
        var p = v.superview, hops = 0
        while let s = p, hops < 4 {
            if s is UIControl || s is UITextField || s is UITextView { return false }
            p = s.superview; hops += 1
        }
        return true
    }
}

private struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded { UIApplication.shared.endEditingEverywhere() }
        )
    }
}

extension View {
    /// Tap anywhere on this view (including over content) to dismiss the keyboard.
    func keyboardDismissOnTap() -> some View { modifier(DismissKeyboardOnTap()) }

    /// Global keyboard behavior: interactive drag-to-dismiss. (Tap-to-dismiss is
    /// handled app-wide by `KeyboardDismissInstaller`, so this only adds the
    /// scroll-drag affordance and is safe to apply broadly via `pulseScreen()`.)
    func dismissesKeyboard() -> some View {
        self.scrollDismissesKeyboard(.interactively)
    }

    /// Back-compat shim for existing call sites. Prefer `dismissesKeyboard()`.
    func dismissKeyboardOnTap() -> some View { dismissesKeyboard() }
}
