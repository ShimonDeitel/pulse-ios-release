import Foundation
import LocalAuthentication

/// Thin wrapper around LocalAuthentication for Face ID / Touch ID flows.
enum BiometricAuth {

    enum BioError: LocalizedError {
        case notAvailable
        case userCancelled
        case userFallback
        case authFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable:        return "Face ID / Touch ID is not available on this device."
            case .userCancelled:       return "Authentication was cancelled."
            case .userFallback:        return "Fallback authentication chosen."
            case .authFailed(let m):   return m
            }
        }
    }

    /// What biometric the device supports, in a user-friendly form.
    static var biometryName: String {
        let context = LAContext()
        var err: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch context.biometryType {
        case .faceID:    return "Face ID"
        case .touchID:   return "Touch ID"
        case .opticID:   return "Optic ID"
        default:         return "Biometrics"
        }
    }

    /// True if device has biometrics set up.
    static var isAvailable: Bool {
        let context = LAContext()
        var err: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    /// Prompt for biometric authentication. Falls back to device passcode if biometrics fail.
    /// Returns true on success, throws on cancel / error.
    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        var err: NSError?
        // Use deviceOwnerAuthentication (biometric + passcode fallback) so
        // users without Face ID set up can still verify.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            throw BioError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: true)
                    return
                }
                let laError = error as? LAError
                switch laError?.code {
                case .userCancel, .systemCancel, .appCancel:
                    continuation.resume(throwing: BioError.userCancelled)
                case .userFallback:
                    continuation.resume(throwing: BioError.userFallback)
                default:
                    continuation.resume(throwing: BioError.authFailed(error?.localizedDescription ?? "Authentication failed"))
                }
            }
        }
    }
}
