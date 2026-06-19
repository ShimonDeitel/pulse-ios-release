import SwiftUI
import CoreData
import UserNotifications
import PhotosUI

// MARK: - Profile View (CloudDesign: MyProfile + Settings combined)

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @FetchRequest(sortDescriptors: [], animation: .default)
    private var profiles: FetchedResults<UserProfile>
    @State private var showingUpgrade = false
    @State private var showingManageSubscription = false
    @State private var showingSignOutConfirm = false
    @State private var showingDeleteAccountConfirm = false
    @State private var showingFinalDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String? = nil
    @AppStorage("pulse_color_scheme") private var colorSchemePreference: String = "system"
    // Sheet states for interactive settings
    @State private var showingPersonalInfo = false
    @State private var showingNotifications = false
    @State private var showingYourData = false
    @State private var showingHelpFAQ = false
    @State private var showingAbout = false
    @State private var isTranslating = false

    // Observe SocialStore so the saved-quotes count and avatar refresh live
    // instead of reading stale values off the bare singleton.
    @ObservedObject private var social = SocialStore.shared

    private var profile: UserProfile? { profiles.first }
    private var subscription: SubscriptionManager { .shared }
    private var localization: LocalizationManager { .shared }

    /// Every pulse (DailyTask) across all of the user's goals.
    private var allPulses: [DailyTask] {
        (profile?.goalsArray ?? []).flatMap { $0.dailyTasksArray }
    }
    private var totalPulsesCount: Int { allPulses.count }
    private var donePulsesCount: Int { allPulses.filter { $0.isCompleted }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // -- Avatar + Name --
                VStack(spacing: 14) {
                    // Profile photo is display-only — the ability to add/change
                    // a picture has been removed. Shows the user's initial.
                    MyAvatarView(size: 88,
                                 initial: String((profile?.displayNameValue ?? "U").prefix(1)).uppercased(),
                                 color: PulseColors.ink)

                    HStack(spacing: 8) {
                        Text(profile?.displayNameValue ?? "User")
                            .font(.system(size: 28, weight: .semibold))
                            .tracking(-1.12)
                            .foregroundColor(PulseColors.ink)
                        TierBadge(tier: subscription.currentTier)
                            .offset(y: 2)
                    }

                    Text("@\(profile?.displayNameValue.lowercased().replacingOccurrences(of: " ", with: "") ?? "user") \u{00B7} \(subscription.currentTier.displayName.uppercased())")
                        .font(PulseTypography.monoCaption)
                        .monoTracking()
                        .foregroundColor(PulseColors.muted)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                // -- Stats card (4 columns) --
                HStack(spacing: 0) {
                    statColumn(label: "GOALS", value: "\(profile?.activeGoals.count ?? 0)")
                    statDivider
                    statColumn(label: "DONE", value: "\(donePulsesCount)")
                    statDivider
                    statColumn(label: "PULSES", value: "\(totalPulsesCount)")
                    statDivider
                    statColumn(label: "STREAK", value: "\(profile?.currentStreak ?? 0)")
                }
                .background(PulseColors.paper)
                .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, 20)

                // -- Subscription banner — ALWAYS shown. Free → upgrade CTA.
                //    Pro/Max → a distinct gold gradient "active" card that opens
                //    Manage / Cancel (Apple requires an easy in-app cancel path).
                Button {
                    if subscription.isPro { showingManageSubscription = true }
                    else { showingUpgrade = true }
                } label: {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(PulseColors.mono)
                        // Pro gets a warm gold gradient; free gets the red signal glow.
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                subscription.isPro
                                ? LinearGradient(
                                    colors: [PulseColors.gold.opacity(0.55), Color(hex: "8A6D1B").opacity(0.25)],
                                    startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(
                                    colors: [PulseColors.signal.opacity(0.3), Color.clear],
                                    startPoint: .topTrailing, endPoint: .bottomLeading)
                            )
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(subscription.isPro ? PulseColors.gold : PulseColors.signal)
                                    .frame(width: 40, height: 40)
                                Image(systemName: subscription.isPro ? "checkmark.seal.fill" : "crown.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subscription.isPro
                                     ? "\(subscription.currentTier.displayName) is active"
                                     : "Upgrade to Pulse Pro")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(subscription.isPro
                                     ? "Manage or cancel your subscription"
                                     : "$9.99/mo \u{2014} AI plans, chat, unlimited goals")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(16)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.bottom, 24)

                // -- ACCOUNT section --
                sectionHeader("ACCOUNT")
                settingsCard {
                    Button { showingPersonalInfo = true } label: {
                        settingsRowContent(icon: "person", label: "Personal info", detail: {
                            // Show the user's name/username here — not the ugly Apple
                            // private-relay email. (The email still lives inside the
                            // Personal info screen itself.)
                            let name = (profile?.displayNameValue ?? "").trimmingCharacters(in: .whitespaces)
                            return name.isEmpty ? "You" : name
                        }())
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    Button { showingNotifications = true } label: {
                        settingsRowContent(icon: "bell", label: "Notifications", detail: notificationFrequencyLabel)
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    Button { showingYourData = true } label: {
                        settingsRowContent(icon: "square.and.arrow.up", label: "Your Data", detail: "")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 20)

                // -- APPEARANCE section --
                sectionHeader("APPEARANCE")
                settingsCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: colorSchemePreference == "dark" ? "moon" : colorSchemePreference == "light" ? "sun.max" : "circle.lefthalf.filled")
                                .font(.system(size: 17))
                                .foregroundColor(PulseColors.muted)
                                .frame(width: 24)

                            Text("Appearance")
                                .font(.system(size: 14.5))
                                .foregroundColor(PulseColors.ink)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                        Picker("", selection: $colorSchemePreference) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    }
                }
                .padding(.bottom, 20)

                // -- SAVED section --
                sectionHeader("SAVED")
                settingsCard {
                    NavigationLink {
                        SavedQuotesView()
                    } label: {
                        settingsRowContent(icon: "bookmark", label: "Saved Quotes",
                                           detail: social.savedQuotes.isEmpty ? "" : "\(social.savedQuotes.count)")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 20)

                sectionHeader("LEGAL".localized)
                settingsCard {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        settingsRowContent(icon: "lock.shield", label: "Privacy Policy".localized, detail: "")
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        settingsRowContent(icon: "doc.text", label: "Terms of Use".localized, detail: "")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 20)

                // -- APP section --
                sectionHeader("APP".localized)
                settingsCard {
                    Button { showingHelpFAQ = true } label: {
                        settingsRowContent(icon: "questionmark.circle", label: "Help & FAQ".localized, detail: "")
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    Button { showingAbout = true } label: {
                        settingsRowContent(icon: "info.circle", label: "About Pulse".localized, detail: "v1.2.0")
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    Button {
                        showingSignOutConfirm = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17))
                                .foregroundColor(PulseColors.muted)
                                .frame(width: 24)

                            Text("Sign out")
                                .font(.system(size: 14.5))
                                .foregroundColor(PulseColors.ink)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PulseColors.muted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    settingsDivider
                    // Delete Account — Apple 5.1.1(v) requires an in-app path
                    // that erases ALL of the user's data: signs out of Apple and
                    // wipes every local + iCloud (CloudKit) record.
                    Button {
                        showingDeleteAccountConfirm = true
                        PulseHaptics.warning()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.system(size: 17))
                                .foregroundColor(PulseColors.signal)
                                .frame(width: 24)

                            Text("Delete account")
                                .font(.system(size: 14.5))
                                .foregroundColor(PulseColors.signal)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(PulseColors.signal.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: PulseSpacing.screenBottom)
            }
        }
        .pulseScreen()
        .navigationBarHidden(true)
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView()
        }
        .sheet(isPresented: $showingManageSubscription) {
            ManageSubscriptionView()
        }
        .sheet(isPresented: $showingPersonalInfo) {
            PersonalInfoSheet(profile: profile)
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationsSheet()
        }
        .sheet(isPresented: $showingYourData) {
            YourDataSheet()
        }
        .sheet(isPresented: $showingHelpFAQ) {
            HelpFAQSheet()
        }
        .sheet(isPresented: $showingAbout) {
            AboutPulseSheet()
        }
        .alert("Sign Out".localized + "?", isPresented: $showingSignOutConfirm) {
            Button("Sign Out".localized, role: .destructive) { signOut() }
            Button("Cancel".localized, role: .cancel) { }
        } message: {
            Text("Your data will remain on this device. You can sign back in anytime.")
        }
        .alert("Are you sure you want to delete your account?", isPresented: $showingDeleteAccountConfirm) {
            Button("I'm sure", role: .destructive) { showingFinalDeleteConfirm = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If you delete your account, every piece of data will be deleted forever — goals, pulses, photos, progress, and profile. This cannot be undone.")
        }
        .alert("This is permanent", isPresented: $showingFinalDeleteConfirm) {
            Button("Delete", role: .destructive) { performDeleteAccount() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Last chance — everything will be erased forever.")
        }
        .alert("Couldn't delete account", isPresented: .constant(deleteAccountError != nil)) {
            Button("OK") { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .overlay {
            if isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Deleting account…")
                        .tint(PulseColors.signal)
                        .padding(24)
                        .background(PulseColors.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    // MARK: - Helpers

    @AppStorage("pulse_notifications_enabled") private var notificationsEnabled = true

    private var notificationFrequencyLabel: String {
        notificationsEnabled ? "Smart".localized : "Off".localized
    }

    // MARK: - Components

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.8)
                .foregroundColor(PulseColors.ink)
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(PulseColors.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(PulseColors.hair)
            .frame(width: 0.5, height: 36)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(PulseTypography.eyebrow)
            .eyebrowTracking()
            .foregroundColor(PulseColors.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PulseSpacing.screenEdge)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private func settingsRowContent(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(PulseColors.muted)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 14.5))
                .foregroundColor(PulseColors.ink)

            Spacer()

            if !detail.isEmpty {
                Text(detail)
                    .font(PulseTypography.monoCaption)
                    .monoTracking()
                    .foregroundColor(PulseColors.muted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PulseColors.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var settingsDivider: some View {
        Divider().frame(height: 0.5).background(PulseColors.hair)
    }

    private func signOut() {
        AuthManager.shared.signOut()
        appState.isAuthenticated = false
        appState.isOnboardingComplete = false
        appState.showOnboardingTour = false
        PulseHaptics.success()
    }

    /// Permanently delete the account + ALL data (Apple 5.1.1(v)). Signs out of
    /// Sign in with Apple, wipes every local + iCloud (CloudKit) record, then
    /// routes back to the auth screen.
    private func performDeleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await AuthManager.shared.deleteAccount()
                await MainActor.run {
                    isDeletingAccount = false
                    appState.isAuthenticated = false
                    appState.isOnboardingComplete = false
                    appState.showOnboardingTour = false
                    PulseHaptics.success()
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteAccountError = "We couldn't delete your account. For security, please sign out, sign back in, and try again. (\(error.localizedDescription))"
                }
            }
        }
    }
}

// MARK: - Personal Info Sheet

private struct PersonalInfoSheet: View {
    let profile: UserProfile?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var revealedPassword: String? = nil
    @State private var revealError: String? = nil
    @State private var hasChanges = false

    // Source of truth for the sign-in provider, in priority order:
    //   1. The value we PERSISTED to Core Data at sign-in (`profile.authProvider`)
    //      — survives app relaunches and the simulator auto-auth path where the
    //      in-memory AuthManager session is never populated.
    //   2. The live in-memory session, if present.
    //   3. Apple — it is the ONLY sign-in method Pulse offers, so it is the only
    //      correct default. (The old `.email` default is what made this screen
    //      say "signed in with email" + show password dots for Apple users.)
    private var provider: AuthProvider {
        if let raw = profile?.authProvider?.lowercased(),
           let p = AuthProvider(rawValue: raw) { return p }
        if let p = AuthManager.shared.currentUser?.provider { return p }
        return .apple
    }
    private var hasPassword: Bool { provider == .email }
    private var signInMethodLabel: String {
        switch provider {
        case .email:  return "email"
        case .google: return "Google"
        case .apple:  return "Apple"
        }
    }
    private var signInMethodIcon: String {
        switch provider {
        case .email:  return "envelope.fill"
        case .google: return "globe"
        case .apple:  return "applelogo"
        }
    }

    // MARK: - Honest account status
    // The account row must reflect REALITY: confirm "Signed in" ONLY when there
    // is a genuine account. Prefer the durable persisted provider (survives
    // relaunch + the simulator auto-auth path where the in-memory session is
    // empty) and fall back to the live session. Never show a green "signed in"
    // seal when no account exists.
    private var isSignedIn: Bool {
        if let raw = profile?.authProvider, !raw.isEmpty { return true }
        return AuthManager.shared.isAuthenticated
    }
    private var accountRowIcon: String {
        isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark"
    }
    private var accountRowTint: Color {
        isSignedIn ? PulseColors.signal : PulseColors.muted
    }
    private var accountRowTitle: String {
        isSignedIn ? "Signed in with \(signInMethodLabel.capitalized)" : "Not signed in"
    }
    private var accountRowSubtitle: String {
        isSignedIn ? "Secured by your Apple ID."
                   : "Sign in with Apple to secure your account and sync your data."
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Avatar
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(PulseColors.paper)
                                .frame(width: 80, height: 80)
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(PulseColors.ink)
                        }
                    }

                    // Account confirmation — proves the account is real.
                    // (The old "Backed up to iCloud" row was removed: it only
                    // checked iCloud sign-in, not real sync, so it could falsely
                    // claim data was backed up.)
                    VStack(spacing: 0) {
                        confirmRow(icon: accountRowIcon, tint: accountRowTint,
                                   title: accountRowTitle,
                                   subtitle: accountRowSubtitle)
                    }
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Display Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISPLAY NAME")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.muted)
                        TextField("Your name", text: $displayName)
                            .font(.system(size: 15))
                            .foregroundColor(PulseColors.ink)
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onChange(of: displayName) { hasChanges = true }
                    }

                    // Email
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EMAIL ADDRESS")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.muted)
                        HStack {
                            Text(email)
                                .font(.system(size: 15))
                                .foregroundColor(PulseColors.ink)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(PulseColors.muted)
                        }
                        .padding(14)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Password — Face ID / Touch ID gated reveal (email accounts only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PASSWORD")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.muted)
                        if hasPassword {
                            HStack {
                                if let pwd = revealedPassword {
                                    Text(pwd)
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundColor(PulseColors.ink)
                                        .textSelection(.enabled)
                                } else {
                                    Text("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundColor(PulseColors.muted)
                                }
                                Spacer()
                                Button {
                                    if revealedPassword == nil {
                                        revealPasswordWithBiometrics()
                                    } else {
                                        revealedPassword = nil
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: revealedPassword == nil ? "faceid" : "eye.slash")
                                            .font(.system(size: 14))
                                        Text(revealedPassword == nil ? "Show".localized : "Hide".localized)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(PulseColors.signal)
                                }
                            }
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            if let err = revealError {
                                Text(err)
                                    .font(PulseTypography.labelSmall)
                                    .foregroundColor(PulseColors.signal)
                            } else {
                                Text("Tap \"Show\" and use \(BiometricAuth.biometryName) to reveal your password.")
                                    .font(PulseTypography.labelSmall)
                                    .foregroundColor(PulseColors.muted)
                            }
                        } else {
                            // No password — signed in with Google / Apple.
                            HStack {
                                Text("No password set")
                                    .font(.system(size: 15))
                                    .foregroundColor(PulseColors.muted)
                                Spacer()
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(PulseColors.muted)
                            }
                            .padding(14)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("You sign in with \(signInMethodLabel) — there's no password on this account.")
                                .font(PulseTypography.labelSmall)
                                .foregroundColor(PulseColors.muted)
                        }
                    }

                    // Sign-in method
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SIGN-IN METHOD")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.muted)
                        HStack(spacing: 10) {
                            Image(systemName: signInMethodIcon)
                                .font(.system(size: 15))
                                .foregroundColor(PulseColors.ink)
                            Text("Sign in with \(signInMethodLabel)")
                                .font(.system(size: 15))
                                .foregroundColor(PulseColors.ink)
                            Spacer()
                        }
                        .padding(14)
                        .background(PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Member Since
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MEMBER SINCE")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.muted)
                        Text(memberSinceDate)
                            .font(.system(size: 15))
                            .foregroundColor(PulseColors.muted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // User ID
                    VStack(alignment: .leading, spacing: 8) {
                        Text("USER ID")
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.muted)
                        Text(profile?.id?.uuidString.prefix(8).uppercased() ?? "—")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(PulseColors.muted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Spacer(minLength: 40)
                }
                .padding(PulseSpacing.screenEdge)
            }
            .pulseScreen()
            .navigationTitle("Personal info".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: hasChanges ? .semibold : .regular))
                    .foregroundColor(hasChanges ? PulseColors.signal : PulseColors.ink)
                }
            }
        }
        .onAppear {
            displayName = profile?.displayNameValue ?? ""
            // Prefer the live session email, fall back to the email we persisted
            // to Core Data at sign-in. With Sign in with Apple the user can choose
            // to hide their address, so an empty value is normal — show that
            // plainly instead of the misleading "Not signed in".
            let live = AuthManager.shared.currentUser?.displayEmail ?? ""
            let stored = profile?.email ?? ""
            if !live.isEmpty {
                email = live
            } else if !stored.isEmpty {
                email = stored
            } else {
                email = "Hidden \u{00B7} Apple Private Relay"
            }
        }
    }

    private func confirmRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PulseColors.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(PulseColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }


    private var memberSinceDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        if let created = profile?.id != nil ? Date() : nil {
            return formatter.string(from: created)
        }
        return "Unknown"
    }

    private func saveChanges() {
        guard hasChanges, let profile = profile else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profile.displayName = trimmed
        try? viewContext.save()
        PulseHaptics.success()
    }

    private func revealPasswordWithBiometrics() {
        revealError = nil
        Task {
            do {
                _ = try await BiometricAuth.authenticate(
                    reason: "Verify it's you to view your password."
                )
                if let stored = KeychainManager.shared.retrieve(key: .userPassword), !stored.isEmpty {
                    await MainActor.run {
                        revealedPassword = stored
                        PulseHaptics.success()
                    }
                } else {
                    await MainActor.run {
                        revealError = "No password on file. Sign in again with your password and we'll save it securely."
                    }
                }
            } catch BiometricAuth.BioError.notAvailable {
                await MainActor.run {
                    revealError = "Face ID / Touch ID isn't set up on this device."
                }
            } catch BiometricAuth.BioError.userCancelled {
                // User backed out — quiet failure, no error message
            } catch {
                await MainActor.run {
                    revealError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Notifications Sheet
// User only toggles notifications on/off. The AI decides WHEN to send them
// based on streak risk, deadline pressure, time since last pulse, and the
// user's chosen mentor personality. No manual scheduling.

private struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pulse_notifications_enabled") private var notificationsEnabled = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Single toggle — that's it.
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Push Notifications".localized)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PulseColors.ink)
                            Text("Pulse decides when. We watch your habits, streak, and deadline.".localized)
                                .font(.system(size: 12))
                                .foregroundColor(PulseColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $notificationsEnabled)
                            .tint(PulseColors.signal)
                            .labelsHidden()
                    }
                    .padding(16)
                }
                .background(PulseColors.paper)
                .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                // What Pulse sends — adaptive list explaining the AI decisions.
                VStack(alignment: .leading, spacing: 12) {
                    Text("WHAT PULSE WATCHES".localized)
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)

                    notifInfoRow(icon: "flame",
                                 text: "Streak about to break — nudge before midnight".localized)
                    notifInfoRow(icon: "clock.arrow.circlepath",
                                 text: "No pulse completed today — gentle reminder at your usual active hour".localized)
                    notifInfoRow(icon: "calendar.badge.exclamationmark",
                                 text: "Deadline pressure rising — daily check-in in the final week".localized)
                    notifInfoRow(icon: "sparkles",
                                 text: "Milestone unlocked — celebrate the win".localized)
                    notifInfoRow(icon: "bubble.left.and.bubble.right",
                                 text: "Chat has something to say — tuned to your personality choice".localized)
                }
                .padding(16)
                .background(PulseColors.paper)
                .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                Spacer()
            }
            .padding(PulseSpacing.screenEdge)
            .pulseScreen()
            .navigationTitle("Notifications".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done".localized) {
                        AdaptiveNotificationScheduler.shared.refresh(enabled: notificationsEnabled)
                        dismiss()
                    }
                    .foregroundColor(PulseColors.ink)
                }
            }
            .onChange(of: notificationsEnabled) {
                AdaptiveNotificationScheduler.shared.refresh(enabled: notificationsEnabled)
            }
        }
    }

    private func notifInfoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(PulseColors.signal)
                .frame(width: 20)
            Text(text)
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Privacy Sheet

private struct YourDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var exportURL: URL?
    @State private var showingDeleteConfirm = false
    @State private var showingFinalDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // -- Data & Account --
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR DATA & ACCOUNT")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)
                        .padding(.bottom, 8)

                    if let url = exportURL {
                        ShareLink(item: url) {
                            dataRow(icon: "square.and.arrow.up", label: "Export my data",
                                    detail: "Ready", tint: PulseColors.ink)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            exportURL = DataExporter.exportFileURL(context: viewContext)
                            PulseHaptics.light()
                        } label: {
                            dataRow(icon: "square.and.arrow.up", label: "Export my data",
                                    detail: "JSON", tint: PulseColors.ink)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().background(PulseColors.hair)

                    Button {
                        showingDeleteConfirm = true
                        PulseHaptics.warning()
                    } label: {
                        dataRow(icon: "trash", label: "Delete account",
                                detail: "", tint: PulseColors.signal)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
                .padding(16)
                .background(PulseColors.paper)
                .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                Text("Deleting your account permanently removes your profile, goals, and data from this device and our servers. This can't be undone.")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)
                    .padding(.horizontal, 4)

                Spacer()
            }
            .padding(PulseSpacing.screenEdge)
            .pulseScreen()
            .navigationTitle("Your Data".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(PulseColors.ink)
                }
            }
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Deleting account…")
                            .tint(PulseColors.signal)
                            .padding(24)
                            .background(PulseColors.paper)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .alert("Delete account?", isPresented: $showingDeleteConfirm) {
                Button("Continue", role: .destructive) { showingFinalDeleteConfirm = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all your data. This cannot be undone. Consider exporting your data first.")
            }
            .alert("This is permanent", isPresented: $showingFinalDeleteConfirm) {
                Button("Delete my account", role: .destructive) { performDelete() }
                Button("Keep my account", role: .cancel) {}
            } message: {
                Text("Are you absolutely sure? Your profile, goals, streaks, and history will be erased forever.")
            }
            .alert("Couldn't delete account", isPresented: .constant(deleteError != nil)) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func dataRow(icon: String, label: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(tint)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14.5))
                .foregroundColor(tint)
            Spacer()
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundColor(PulseColors.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PulseColors.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func performDelete() {
        isDeleting = true
        Task {
            do {
                try await AuthManager.shared.deleteAccount()
                // signOut() inside deleteAccount posts .pulseUserDidSignOut,
                // which routes the app back to the auth screen. Just close.
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "We couldn't delete your account. For security, please sign out, sign back in, and try again. (\(error.localizedDescription))"
                }
            }
        }
    }

}

// (LanguagePickerSheet removed — English-only build.)
// (RegionPickerSheet removed — region feature removed.)

// MARK: - Help & FAQ Sheet

private struct HelpFAQSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedQuestion: Int?
    @State private var aiQuestion = ""
    @State private var aiAnswer = ""
    @State private var isAskingAI = false

    private let faqItems: [(question: String, answer: String)] = [
        ("How do I create a goal?", "Tap the + button on the Goals tab or the Create Goal button on the dashboard. Choose between a standard goal, challenge, daily habit, or transformation. Follow the guided flow to set your goal details, timeline, and daily tasks."),
        ("What's the difference between goal types?", "Standard Goal: AI creates a full roadmap with pulses. Challenge: Short-term sprint (7, 14, or 30 days). Daily Habit: Recurring daily task with streak tracking. Transformation: Upload before/goal photos and AI builds your plan."),
        ("How does the streak system work?", "Complete at least one task every day to maintain your streak. Your streak resets if you miss a full day. Longer streaks earn bonus XP and unlock achievements."),
        ("What are Pulses (XP)?", "Pulses are experience points earned by completing tasks, maintaining streaks, and hitting milestones. They contribute to your level progression. Most pulses earn 10 XP; workout and transformation pulses earn 15 XP."),
        ("How does the AI chat work?", "The AI chat analyzes your goals and progress to provide personalized advice, suggestions, and motivation. Chat with it anytime from the Chat tab. You can choose from 10 different personalities."),
        ("How do I set up AI?", "Nothing to set up — AI is built into Pulse and powers the AI chat, goal analysis, and roadmap generation. AI is free for everyone — no upgrade needed. Pro just adds unlimited goals and Primary Access (priority AI when servers are busy)."),
        ("Can I change my goal after creating it?", "Yes, tap on any goal to view its details. You can complete pulses, ask the AI about specific steps, and track your progress."),
        ("How do notifications work?", "Go to Profile → Notifications and turn reminders on or off. When on, Pulse picks the best times to nudge you based on your streak, deadlines, and activity — there's no fixed schedule to set."),
        ("Where is my data stored?", "All your data is stored on your device and syncs privately across your devices via Apple iCloud (CloudKit). The only things that leave your device are the contents of your AI conversations and any photos you submit for meal scanning or photo analysis, which are sent to our AI provider (Google's Gemini API) to generate a response and are not stored on our servers afterward. Your live-workout camera feed is processed entirely on your device and is never uploaded."),
        ("How do I upgrade to Pro?", "Go to your Profile tab and tap the upgrade banner. Pro adds unlimited goals and Primary Access — priority AI, no waiting when servers are busy. The AI coach itself is free for everyone."),
        ("How do I delete my data?", "Go to Profile → Your Data, or use Delete Account on your Profile. You can export your data as JSON or delete everything from the app."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // Ask AI card
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.system(size: 16))
                                .foregroundColor(PulseColors.signal)
                            Text("Ask AI")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(PulseColors.ink)
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            TextField("Ask anything about Pulse...", text: $aiQuestion)
                                .font(.system(size: 14))
                                .foregroundColor(PulseColors.ink)
                                .padding(12)
                                .background(PulseColors.surfaceContainer)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Button {
                                Task { await askAI() }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(aiQuestion.isEmpty ? PulseColors.muted : PulseColors.signal)
                            }
                            .disabled(aiQuestion.isEmpty || isAskingAI)
                        }

                        if isAskingAI {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(PulseTypography.labelSmall)
                                    .foregroundColor(PulseColors.muted)
                            }
                        }

                        if !aiAnswer.isEmpty {
                            Text(aiAnswer)
                                .font(.system(size: 13.5))
                                .foregroundColor(PulseColors.ink)
                                .lineSpacing(3)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PulseColors.signal.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(16)
                    .background(PulseColors.paper)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                    // FAQ section header
                    Text("FREQUENTLY ASKED QUESTIONS")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    ForEach(Array(faqItems.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(PulseAnimations.gentle) {
                                    expandedQuestion = expandedQuestion == index ? nil : index
                                }
                            } label: {
                                HStack {
                                    Text(item.question)
                                        .font(.system(size: 14.5, weight: .medium))
                                        .foregroundColor(PulseColors.ink)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: expandedQuestion == index ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(PulseColors.muted)
                                }
                                .padding(16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if expandedQuestion == index {
                                Divider().frame(height: 0.5).background(PulseColors.hair)
                                Text(item.answer)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(PulseColors.muted)
                                    .lineSpacing(3)
                                    .padding(16)
                            }
                        }
                        .background(PulseColors.paper)
                        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                    }
                }
                .padding(PulseSpacing.screenEdge)
            }
            .pulseScreen()
            .navigationTitle("Help & FAQ".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(PulseColors.ink)
                }
            }
        }
    }

    private func askAI() async {
        guard !aiQuestion.isEmpty else { return }
        isAskingAI = true
        aiAnswer = ""

        do {
            let response = try await GeminiAPIService.shared.sendMessage(
                userMessage: aiQuestion,
                systemPrompt: "You are the help assistant for Pulse, an AI-powered goal achievement app. Answer questions about how the app works, its features, and troubleshooting. Be concise and helpful. Keep answers to 2-3 short paragraphs.",
                temperature: 0.5
            )
            aiAnswer = response
        } catch {
            aiAnswer = "Unable to get a response right now. Please check your connection and try again.\n\nError: \(error.localizedDescription)"
        }
        isAskingAI = false
    }
}

// MARK: - About Pulse Sheet

private struct AboutPulseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(PulseColors.signal)

                    Text("Pulse Goals")
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-1.12)
                        .foregroundColor(PulseColors.ink)

                    Text("Version 1.2.0 (Build 42)")
                        .font(PulseTypography.monoCaption)
                        .monoTracking()
                        .foregroundColor(PulseColors.muted)
                }
                .padding(.top, 20)

                VStack(spacing: 0) {
                    aboutRow(label: "Developer", value: "Pulse Labs")
                    Divider().frame(height: 0.5).background(PulseColors.hair)
                    aboutRow(label: "Platform", value: "iOS 17+")
                    Divider().frame(height: 0.5).background(PulseColors.hair)
                    aboutRow(label: "Framework", value: "SwiftUI + Core Data")
                }
                .background(PulseColors.paper)
                .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ACKNOWLEDGMENTS")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)

                    Text("Pulse uses Google's Gemini API for AI features, and Apple — Sign in with Apple and iCloud / CloudKit — for authentication and private cloud sync.")
                        .font(.system(size: 13.5))
                        .foregroundColor(PulseColors.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("CONTENT FILTERING")
                        .font(PulseTypography.eyebrow)
                        .eyebrowTracking()
                        .foregroundColor(PulseColors.muted)

                    Text("Pulse has a built-in content filter that keeps everything appropriate for ages 13 and up. It applies everywhere — including AI chat replies — and is always on. It can't be turned off.")
                        .font(.system(size: 13.5))
                        .foregroundColor(PulseColors.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(PulseSpacing.screenEdge)
            .pulseScreen()
            .navigationTitle("About Pulse".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(PulseColors.ink)
                }
            }
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundColor(PulseColors.ink)
            Spacer()
            Text(value)
                .font(PulseTypography.monoCaption)
                .monoTracking()
                .foregroundColor(PulseColors.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
