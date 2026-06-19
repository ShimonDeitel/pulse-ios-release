import SwiftUI
import AuthenticationServices
import CoreData

// MARK: - Auth Welcome Screen (Sign in with Apple)

/// The single sign-in surface. Sign in with Apple is the only method: identity
/// comes straight from Apple, private data syncs via CloudKit, and there is no
/// password, server, or third-party auth to maintain.
struct AuthWelcomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentOpacity: CGFloat = 0
    @State private var contentOffset: CGFloat = 24
    @State private var appleSignInError: String?
    @State private var isAppleLoading = false
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            PulseColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Logo + wordmark (top-left) ────────────────────
                HStack(spacing: 8) {
                    MiniPulseView(width: 48, height: 20)

                    Text("Pulse Goals")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.44) // -0.02em at 22px
                        .foregroundColor(PulseColors.ink)

                    Spacer()
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 40)

                Spacer()

                // ── Headline block ─────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("SIGN IN")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)

                    // "What are you chasing this year?"
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What are you")
                            .font(.system(size: 36, weight: .semibold))
                            .tracking(-1.44) // -0.04em at 36px
                            .foregroundColor(PulseColors.ink)
                        HStack(spacing: 0) {
                            Text("chasing")
                                .font(.system(size: 36, weight: .semibold))
                                .tracking(-1.44)
                                .foregroundColor(PulseColors.signal)
                            Text(" this year?")
                                .font(.system(size: 36, weight: .semibold))
                                .tracking(-1.44)
                                .foregroundColor(PulseColors.ink)
                        }
                    }

                    Text("Sign in to save your goals across devices.")
                        .font(.system(size: 15))
                        .foregroundColor(PulseColors.muted)
                        .lineSpacing(15 * 0.45 - 15)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, 28)

                // ── Auth button ───────────────────────────────────
                VStack(spacing: 10) {
                    // Continue with Apple — native button (App Store compliant)
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, 32)

                // ── Footer: terms + privacy (tappable, readable) ──────
                VStack(spacing: 8) {
                    Divider()
                        .frame(height: 0.5)
                        .background(PulseColors.hair)

                    Text("By continuing, you agree to our Terms of Use and Privacy Policy.")
                        .font(.system(size: 11.5))
                        .foregroundColor(PulseColors.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(11.5 * 0.4)
                        .padding(.top, 16)

                    HStack(spacing: 18) {
                        Button("Terms of Use") { showTerms = true }
                        Text("·").foregroundColor(PulseColors.muted)
                        Button("Privacy & Security") { showPrivacy = true }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .tint(PulseColors.signal)
                    .foregroundColor(PulseColors.signal)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)

            // Apple loading overlay
            if isAppleLoading {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView()
                    .tint(PulseColors.signal)
                    .scaleEffect(1.2)
            }
        }
        .onAppear {
            withAnimation(PulseAnimations.reveal.delay(0.15)) {
                contentOpacity = 1
                contentOffset = 0
            }
        }
        .alert("Error", isPresented: .constant(appleSignInError != nil)) {
            Button("OK") { appleSignInError = nil }
        } message: {
            Text(appleSignInError ?? "")
        }
        .sheet(isPresented: $showTerms) {
            LegalConsentSheet(title: "Terms of Use") { showTerms = false } content: {
                TermsOfServiceView()
            }
        }
        .sheet(isPresented: $showPrivacy) {
            LegalConsentSheet(title: "Privacy & Security") { showPrivacy = false } content: {
                PrivacyPolicyView()
            }
        }
    }

    // MARK: - Sign in with Apple

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleSignInError = "Apple Sign-In failed. Please try again."
                PulseHaptics.error()
                return
            }
            Task { await completeAppleSignIn(credential: credential) }
        case .failure(let error):
            // Silent ONLY on a real user cancellation. Other codes — including
            // .unknown (1000), which a misconfigured Sign in with Apple
            // capability/entitlement surfaces — must be shown, not swallowed, or
            // the user is left stuck with a button that does nothing.
            if let authError = error as? ASAuthorizationError {
                if authError.code == .canceled { return }
                print("[Auth] Sign in with Apple failed: code=\(authError.code.rawValue) \(error.localizedDescription)")
            }
            // And never nag if we're actually signed in — only a genuine,
            // unauthenticated failure deserves the dialog.
            if AuthManager.shared.isAuthenticated || appState.isAuthenticated { return }
            appleSignInError = error.localizedDescription
            PulseHaptics.error()
        }
    }

    private func completeAppleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        isAppleLoading = true
        appleSignInError = nil
        // Apple only returns the user's name on the FIRST authorization, so
        // capture it here before handing the credential to AuthManager.
        let appleName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        do {
            try await AuthManager.shared.signInWithApple(credential: credential)
            await MainActor.run {
                let profile = UserProfile.fetchOrCreate(in: viewContext)
                // Persist the email Apple returned (may be empty if the user
                // chose to hide it behind Private Relay).
                let resolvedEmail = AuthManager.shared.currentUser?.email ?? ""
                if !resolvedEmail.isEmpty { profile.email = resolvedEmail }

                // Capture the user's name. Apple only sends it on the FIRST
                // authorization, so: store it if we got it; otherwise, if we
                // still have no real name, fall back to the session name or a
                // sensible email handle — and if everything is empty, leave it
                // nil so the in-app name prompt asks for it (never hard-code
                // "User", which is what made the profile read "User").
                if !appleName.isEmpty {
                    profile.displayName = appleName
                } else if !profile.hasRealName {
                    let sessionName = AuthManager.shared.currentUser?.displayName ?? ""
                    let handle = (resolvedEmail.contains("@") && !resolvedEmail.contains("privaterelay"))
                        ? (resolvedEmail.components(separatedBy: "@").first?.capitalized ?? "")
                        : ""
                    if !sessionName.isEmpty { profile.displayName = sessionName }
                    else if !handle.isEmpty { profile.displayName = handle }
                    else { profile.displayName = "Athlete" }   // friendly fallback — no name prompt
                }

                profile.authProvider = "apple"
                profile.onboardingCompleted = true
                profile.lastActiveDate = Date()
                try? viewContext.save()
                appState.isAuthenticated = true
                appState.isOnboardingComplete = true
                // Persist for the next cold launch — avoids the launch
                // screen flashing while Core Data loads.
                UserDefaults.standard.set(true, forKey: "pulse_onboarding_complete")
                appState.showOnboardingTour = !profile.onboardingTourCompleted
                appState.needsNameEntry = false   // name prompt removed
                PulseHaptics.success()
            }
        } catch {
            await MainActor.run {
                // Only surface a GENUINE failure. If a non-fatal downstream step
                // (e.g. minting the AI session token) threw after the Apple
                // identity was already established, the user IS signed in — don't
                // pop an annoying error on top of a successful sign-in.
                if !AuthManager.shared.isAuthenticated && !appState.isAuthenticated {
                    appleSignInError = error.localizedDescription
                    PulseHaptics.error()
                }
            }
        }
        await MainActor.run { isAppleLoading = false }
    }
}

// MARK: - Legal consent sheet
//
// Presents the full, readable Terms of Use / Privacy & Security text, a link to
// the marketing website for the complete details, and an explicit "I Agree"
// button that records consent. There is intentionally no "I don't agree" —
// continuing to use the app constitutes agreement.
private struct LegalConsentSheet<Content: View>: View {
    let title: String
    let onAgree: () -> Void
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(title: String, onAgree: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onAgree = onAgree
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }.foregroundColor(PulseColors.ink)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        Link(destination: URL(string: "https://shimondeitel.github.io/pulse-goals/privacy.html")!) {
                            HStack(spacing: 5) {
                                Image(systemName: "safari")
                                Text("Read the full details on our website")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(PulseColors.signal)
                        }
                        Button {
                            PulseHaptics.success()
                            onAgree()
                            dismiss()
                        } label: {
                            Text("I Agree")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(PulseColors.signal)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, PulseSpacing.screenEdge)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                }
        }
    }
}
