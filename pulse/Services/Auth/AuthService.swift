import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Auth Session (Keychain-backed)

/// A signed-in identity. With Sign in with Apple this is derived entirely from
/// the `ASAuthorizationAppleIDCredential` — there is no server, no password, and
/// no refresh token. `userId` is Apple's stable, app-scoped user identifier
/// (`credential.user`), which is the same across the user's devices and reinstalls.
struct AuthSession: Sendable {
    let userId: String
    let email: String
    let displayName: String?
    let provider: AuthProvider
    let idToken: String          // Apple identity token (JWT). Not validated server-side.
    let refreshToken: String     // Always "" for Apple — kept for struct compatibility.
    let expiresAt: Date

    var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt // 60s buffer
    }

    var isValid: Bool {
        !userId.isEmpty && !isExpired
    }

    /// Email to display to the user: the address Apple returned directly, or —
    /// when Apple only embedded it in the identity token (common on returning
    /// sign-ins) — the `email` claim decoded from that token. Display-only; the
    /// signature is NOT validated here.
    var displayEmail: String {
        if !email.isEmpty { return email }
        return AuthSession.appleEmail(fromIdentityToken: idToken) ?? ""
    }

    /// Decode the `email` claim from an Apple identity-token JWT, if present.
    /// Reads the unverified payload segment only — for display, never for trust.
    static func appleEmail(fromIdentityToken token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var b64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String, !email.isEmpty else { return nil }
        return email
    }
}

enum AuthProvider: String, Codable, Sendable {
    case email, apple, google
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidEmail
    case invalidPassword
    case invalidCode(String)
    case codeExpired
    case rateLimited(String)
    case networkError
    case serverError(String)
    case appleSignInFailed
    case userNotFound
    case emailAlreadyInUse
    case tokenRefreshFailed
    case sessionExpired
    case noSession
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Please enter a valid email address."
        case .invalidPassword: return "Password must be at least 12 characters with uppercase, lowercase, number, and symbol."
        case .invalidCode(let msg): return msg
        case .codeExpired: return "Code expired. Please request a new one."
        case .rateLimited(let msg): return msg
        case .networkError: return "Unable to connect. Please check your connection."
        case .serverError(let msg): return msg
        case .appleSignInFailed: return "Apple Sign In failed. Please try again."
        case .userNotFound: return "No account found with this email."
        case .emailAlreadyInUse: return "An account with this email already exists."
        case .tokenRefreshFailed: return "Session refresh failed. Please sign in again."
        case .sessionExpired: return "Your session has expired. Please sign in again."
        case .noSession: return "No active session."
        case .unknown(let msg): return msg
        }
    }
}

// MARK: - Auth Lifecycle Notifications

extension Notification.Name {
    /// Fires after AuthManager.signOut wipes local persistence. UI layers should
    /// re-query their data sources (which are now empty) so they reset to empty.
    static let pulseUserDidSignOut = Notification.Name("pulseUserDidSignOut")
    /// Fires after a fresh sign-in. CloudKit re-hydrates the local store from the
    /// user's private iCloud database automatically; observers can use this to
    /// refresh once that lands.
    static let pulseUserDidSignIn = Notification.Name("pulseUserDidSignIn")
}

// MARK: - Auth Manager (Observable Singleton)

/// Native Sign in with Apple. No backend, no Firebase, no email/password.
///
/// Identity comes straight from `ASAuthorizationAppleIDCredential`:
/// • `credential.user` is the stable, app-scoped Apple user id → `userId`.
/// • name + email are only provided on the FIRST authorization, so we persist
///   them in the Keychain the first time and reuse them afterwards.
///
/// Private data sync is handled by `NSPersistentCloudKitContainer` against the
/// signed-in Apple ID's private iCloud database — see `PersistenceController`.
@Observable
final class AuthManager {
    static let shared = AuthManager()

    var isAuthenticated = false
    var isLoading = false
    var currentUser: AuthSession?

    private let keychain = KeychainManager.shared

    private init() {
        restoreSession()
    }

    // MARK: - Session Restoration

    /// Restore the cached Apple identity from the Keychain on launch. The user
    /// signs in ONCE per install; only an explicit Sign Out (or the user revoking
    /// the Apple ID in iOS Settings) clears the session.
    private func restoreSession() {
        guard let userId = keychain.retrieve(key: .cognitoUserId), !userId.isEmpty else {
            isAuthenticated = false
            return
        }

        let session = AuthSession(
            userId: userId,
            email: keychain.retrieve(key: .cognitoUserEmail) ?? "",
            displayName: keychain.retrieve(key: .cognitoUserName),
            provider: .apple,
            idToken: keychain.retrieve(key: .cognitoIdToken) ?? "",
            refreshToken: "",
            expiresAt: .distantFuture
        )
        currentUser = session
        isAuthenticated = true

        // Best-effort: verify the Apple credential is still authorized. Only sign
        // out if Apple explicitly reports it revoked / not found — a transient
        // failure (offline, etc.) must NOT log the user out.
        verifyAppleCredentialState(userId: userId)
    }

    private func verifyAppleCredentialState(userId: String) {
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    // MARK: - Sign In with Apple

    /// Persist the Apple credential locally and mark the user signed in. Apple
    /// only hands back the name/email on the FIRST authorization, so we keep any
    /// previously-stored values when this is a returning sign-in.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        isLoading = true
        defer { isLoading = false }

        let userId = credential.user
        guard !userId.isEmpty else { throw AuthError.appleSignInFailed }

        let identityToken = credential.identityToken
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // First-authorization-only fields. Fall back to whatever we stored before.
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let resolvedName = !fullName.isEmpty
            ? fullName
            : keychain.retrieve(key: .cognitoUserName)
        // Apple returns the email directly only on the FIRST authorization; on
        // returning sign-ins it's embedded in the identity token instead — decode
        // it from there before falling back to the previously stored value.
        let resolvedEmail = credential.email
            ?? AuthSession.appleEmail(fromIdentityToken: identityToken)
            ?? keychain.retrieve(key: .cognitoUserEmail)
            ?? ""

        let session = AuthSession(
            userId: userId,
            email: resolvedEmail,
            displayName: resolvedName,
            provider: .apple,
            idToken: identityToken,
            refreshToken: "",
            expiresAt: .distantFuture
        )

        persist(session)
        await finishSignIn(session: session)
    }

    /// Shared post-sign-in path: publish the session, then signal observers.
    /// CloudKit re-hydrates Core Data from the user's private iCloud DB
    /// automatically — there is nothing to fetch here.
    private func finishSignIn(session: AuthSession) async {
        await MainActor.run {
            self.currentUser = session
            self.isAuthenticated = true
            NotificationCenter.default.post(name: .pulseUserDidSignIn, object: nil)
        }
        // Mint the Pulse AI session JWT now, while the Apple identity token is at
        // its freshest. Best-effort: if it fails, the first AI call re-exchanges.
        if ProxyConfig.isEnabled {
            await ProxySessionManager.shared.refreshAtSignIn()
        }
    }

    // MARK: - Fresh Apple identity token (for AI session re-mint)

    /// Re-run Sign in with Apple to obtain a FRESH identity token WITHOUT a full
    /// sign-out. The token captured at sign-in is short-lived (minutes–1h), so
    /// when the AI proxy session needs (re)minting later — e.g. it was never
    /// minted, or lapsed after 60 days — we need a new one. For a user already
    /// signed in with this Apple ID, iOS completes this with a quick Face ID /
    /// brief sheet (no re-registration, no name/email re-prompt). Returns the
    /// fresh token, or nil if it can't be presented or the user cancels. On
    /// success the token is persisted and the in-memory session is refreshed.
    @MainActor
    func refreshAppleIdentityToken() async -> String? {
        guard isAuthenticated else { return nil }
        guard let token = await AppleReauthDriver.requestFreshIdentityToken(),
              !token.isEmpty else { return nil }
        keychain.save(key: .cognitoIdToken, value: token)
        if let u = currentUser {
            currentUser = AuthSession(
                userId: u.userId, email: u.email, displayName: u.displayName,
                provider: .apple, idToken: token, refreshToken: "", expiresAt: .distantFuture
            )
        }
        return token
    }

    // MARK: - Sign Out

    /// Sign out = drop the in-memory SESSION + device-local caches only. It must
    /// NOT delete Core Data rows: the store is an NSPersistentCloudKitContainer
    /// mirrored to the user's PRIVATE iCloud DB, so a batch-delete here would also
    /// erase their goals/workouts from iCloud (the old `wipeAllUserData()` bug
    /// that deleted a user's workout on sign-out). Each Apple ID has its own
    /// private DB, so there's no cross-account leakage to guard against — on the
    /// next sign-in CloudKit re-hydrates the data. True erasure lives only in
    /// `deleteAccount()`.
    func signOut() {
        // Reset the live view + device-local caches (UserDefaults / widget store /
        // local notifications). Does NOT issue persistent deletes, so nothing
        // replicates to CloudKit.
        PersistenceController.shared.resetLocalSessionState()
        keychain.clearAuthTokens()
        keychain.delete(key: .userPassword)

        // Drop the in-memory proxy session JWT too (the Keychain copy is already
        // gone via clearAuthTokens → .proxySessionToken).
        Task { await ProxySessionManager.shared.invalidate() }

        currentUser = nil
        isAuthenticated = false

        // Tell every observer to reset their live view. Data re-hydrates from
        // CloudKit after the next sign-in (it is NOT deleted on sign-out).
        NotificationCenter.default.post(name: .pulseUserDidSignOut, object: nil)
    }

    // MARK: - Delete Account (Apple Guideline 5.1.1(v))

    /// Permanently delete the user's account and every byte of their data.
    ///
    /// With Sign in with Apple there is no server-side account to delete. We:
    ///   (1) best-effort clear any remote data (no-op now that CloudKit owns sync),
    ///   (2) wipe all local data + the keychain identity via the audited sign-out path.
    ///
    /// The user can additionally remove the app from "Sign in with Apple" in
    /// iOS Settings → Apple ID; full server-side token revocation would require a
    /// backend holding the Apple client secret, which this app intentionally
    /// does not run.
    func deleteAccount() async throws {
        // (1) Best-effort remote wipe. No-op under CloudKit, never blocks deletion.
        try? await FirestoreSyncService.shared.deleteAllRemoteData()
        // (2) TRUE erasure: destroy every Core Data row (this DOES propagate the
        //     deletes to the user's private iCloud DB — intended for account
        //     deletion / GDPR), THEN tear down the session. Unlike sign-out, this
        //     is meant to wipe iCloud too.
        await MainActor.run {
            PersistenceController.shared.destroyAllUserDataForAccountDeletion()
            self.signOut()
        }
    }

    // MARK: - Private Helpers

    private func persist(_ session: AuthSession) {
        keychain.save(key: .cognitoUserId, value: session.userId)
        keychain.save(key: .cognitoUserEmail, value: session.email)
        keychain.save(key: .cognitoIdToken, value: session.idToken)
        // Reuse the access-token slot too so any legacy reader stays consistent.
        keychain.save(key: .cognitoAccessToken, value: session.idToken)
        keychain.saveTokenExpiry(session.expiresAt)
        if let name = session.displayName, !name.isEmpty {
            keychain.save(key: .cognitoUserName, value: name)
        }
    }
}

// MARK: - Apple Re-auth Driver
//
// Drives a one-shot `ASAuthorizationController` to obtain a FRESH Apple identity
// token outside the sign-in screen (used to re-mint the AI proxy session when
// the cached token has expired). Bridges the delegate callbacks to async/await.
// MainActor-isolated because it touches UIKit windows and presents UI.
@MainActor
private final class AppleReauthDriver: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<String?, Never>?
    /// Strong ref to the in-flight controller. ASAuthorizationController does NOT
    /// retain itself during a request, and its `delegate`/`presentationContextProvider`
    /// are weak — so without holding it here it gets deallocated the moment
    /// `performRequests()` returns and the request silently dies (no sheet, no
    /// callback). THIS was why re-auth never presented a Face ID prompt.
    private var controller: ASAuthorizationController?
    /// Hold the in-flight driver so ARC doesn't release it mid-request.
    private static var inFlight: AppleReauthDriver?

    static func requestFreshIdentityToken() async -> String? {
        if inFlight != nil { return nil } // one re-auth at a time
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let driver = AppleReauthDriver()
            driver.continuation = cont
            inFlight = driver
            // No requested scopes: we only need a fresh identity token, not the
            // name/email again (those are only ever returned on first authorization).
            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = driver
            controller.presentationContextProvider = driver
            driver.controller = controller // retain until a delegate callback fires
            controller.performRequests()
        }
    }

    private func finish(_ token: String?) {
        continuation?.resume(returning: token)
        continuation = nil
        controller = nil
        AppleReauthDriver.inFlight = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        let token = (authorization.credential as? ASAuthorizationAppleIDCredential)?
            .identityToken
            .flatMap { String(data: $0, encoding: .utf8) }
        finish(token)
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        finish(nil)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first ?? UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
