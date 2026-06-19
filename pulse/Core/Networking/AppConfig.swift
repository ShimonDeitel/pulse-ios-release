import Foundation

// MARK: - App Configuration
//
// To preview the REAL Face ID purchase before shipping: open the project in
// Xcode and RUN on a device (the scheme's StoreKit test config drives the
// purchase sheet — no real charge). For actual money, the owner must create the
// matching auto-renewable product + complete the Paid Apps Agreement/banking/tax
// in App Store Connect (see the runbook); the in-app .storekit file is dev-only.
// A verified StoreKit purchase is the ONLY way to unlock Pro — there is no
// local/no-purchase backdoor.
enum AppConfig {
    /// True in DEBUG builds and in TestFlight (App Store **sandbox** receipt),
    /// false in the public App Store build. Gates internal-only UI so testers
    /// can exercise Pro/AI in TestFlight without it ever appearing for App Store
    /// users.
    static var isTestFlightOrDebug: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
