import SwiftUI

// MARK: - Welcome to Pro
//
// A full-screen celebration shown ONCE when the user unlocks Pulse Pro (real
// purchase or redeem). Rendered at the app root (see PulseApp) so it floats
// above whatever screen triggered it. Auto-dismisses, or tap to continue.

struct WelcomeToProView: View {
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var ringPulse = false
    @State private var sparkle = false

    var body: some View {
        ZStack {
            // Dim + warm glow backdrop
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            RadialGradient(
                colors: [PulseColors.gold.opacity(0.28), .clear],
                center: .center, startRadius: 10, endRadius: 360
            )
            .ignoresSafeArea()
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 22) {
                // Animated emblem
                ZStack {
                    Circle()
                        .stroke(PulseColors.gold.opacity(0.5), lineWidth: 2)
                        .frame(width: 150, height: 150)
                        .scaleEffect(ringPulse ? 1.25 : 0.9)
                        .opacity(ringPulse ? 0 : 0.8)
                    Circle()
                        .fill(
                            LinearGradient(colors: [PulseColors.gold, PulseColors.signal],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 104, height: 104)
                        .shadow(color: PulseColors.gold.opacity(0.5), radius: 18, y: 6)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .rotationEffect(.degrees(appeared ? 0 : -25))
                    // Sparkles
                    ForEach(0..<6, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(PulseColors.gold)
                            .offset(y: -86)
                            .rotationEffect(.degrees(Double(i) / 6 * 360))
                            .scaleEffect(sparkle ? 1 : 0.2)
                            .opacity(sparkle ? 1 : 0)
                    }
                }

                VStack(spacing: 8) {
                    Text("Welcome to Pro")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("Unlimited goals are now yours, plus Primary Access — priority AI whenever you need it.")
                        .font(.system(size: 14.5))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                Button {
                    PulseHaptics.light()
                    onDismiss()
                } label: {
                    Text("Let's go")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(PulseColors.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 36)
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)

                // Apple requires an easy in-app path to manage/cancel subscription.
                // Route through StoreManager, which presents the native
                // manage-subscriptions sheet and falls back to the https URL
                // (the raw itms-apps:// scheme can silently no-op).
                Button {
                    Task { await StoreManager.shared.showManageSubscriptions() }
                } label: {
                    Text("Manage Subscription")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .underline()
                }
                .opacity(appeared ? 1 : 0)
            }
            .padding(.vertical, 40)
        }
        .onAppear {
            PulseHaptics.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) { appeared = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { sparkle = true }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { ringPulse = true }
            // Auto-dismiss so it never traps the user.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { onDismiss() }
        }
    }
}
