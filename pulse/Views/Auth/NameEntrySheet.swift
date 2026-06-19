import SwiftUI
import CoreData

// MARK: - Name Entry Prompt
//
// Sign in with Apple only returns the user's name on the FIRST authorization.
// On returning sign-ins (and on the simulator, which bypasses the real Apple
// flow), we land with just the "User" placeholder. Rather than silently showing
// "User", this one-field sheet asks the user what we should call them, so the
// profile + greetings always use their real name.
struct NameEntrySheet: View {
    let profile: UserProfile?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @FocusState private var nameFieldFocused: Bool
    @State private var name: String = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canContinue: Bool { trimmed.count >= 2 }

    var body: some View {
        ZStack {
            PulseColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("WELCOME")
                    .font(PulseTypography.eyebrow)
                    .eyebrowTracking()
                    .foregroundColor(PulseColors.muted)
                    .padding(.bottom, 12)

                Text("What should we")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1.36)
                    .foregroundColor(PulseColors.ink)
                HStack(spacing: 0) {
                    Text("call you?")
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-1.36)
                        .foregroundColor(PulseColors.signal)
                }
                .padding(.bottom, 10)

                Text("This is just for your profile and your AI's greetings. You can change it anytime in Personal info.")
                    .font(.system(size: 15))
                    .foregroundColor(PulseColors.muted)
                    .lineSpacing(3)
                    .padding(.bottom, 28)

                TextField("Your name", text: $name)
                    .font(.system(size: 17))
                    .foregroundColor(PulseColors.ink)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($nameFieldFocused)
                    .onSubmit { if canContinue { save() } }
                    .padding(16)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Spacer()

                Button { save() } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(canContinue ? PulseColors.signal : PulseColors.signal.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 9999, style: .continuous))
                }
                .disabled(!canContinue)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, PulseSpacing.screenEdge)
        }
        // Must enter a name — this is the whole point of the prompt.
        .interactiveDismissDisabled(true)
        .onAppear {
            // Pre-fill with anything we already have that isn't the placeholder.
            if profile?.hasRealName == true { name = profile?.displayNameValue ?? "" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { nameFieldFocused = true }
        }
    }

    private func save() {
        guard canContinue else { return }
        let profile = self.profile ?? UserProfile.fetchOrCreate(in: viewContext)
        profile.displayName = trimmed
        profile.lastActiveDate = Date()
        try? viewContext.save()
        appState.needsNameEntry = false
        PulseHaptics.success()
    }
}
