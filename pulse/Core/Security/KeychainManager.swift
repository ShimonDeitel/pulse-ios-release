import Foundation
import Security

// MARK: - Keychain Security Levels

/// Security level determines the access control for stored items.
/// Higher levels require biometric/passcode authentication.
enum KeychainSecurityLevel {
    /// Accessible when device is unlocked. Good for general tokens.
    case standard
    /// Requires passcode to be set on device. For auth tokens.
    case requirePasscode
    /// Requires biometric or passcode each access. For the most sensitive data.
    case biometricOrPasscode
}

// MARK: - Keychain Keys

enum KeychainKey: String, CaseIterable {
    // Auth
    case cognitoAccessToken = "cognito_access_token"
    case cognitoRefreshToken = "cognito_refresh_token"
    case cognitoIdToken = "cognito_id_token"
    case cognitoTokenExpiry = "cognito_token_expiry"
    case cognitoUserId = "cognito_user_id"
    case cognitoUserEmail = "cognito_user_email"
    case cognitoUserName = "cognito_user_name"

    // API
    case apiEndpoint = "api_endpoint"

    // Stripe
    case stripeCustomerId = "stripe_customer_id"

    // Legacy (migration)
    case geminiAPIKey = "gemini_api_key"

    // Claude (paid tiers)
    case anthropicAPIKey = "anthropic_api_key"

    // DeepSeek V4 (primary AI engine for all paid tiers)
    case deepSeekAPIKey = "deepseek_api_key"

    // Live web search provider (Tavily / Brave) for AI grounding
    case searchAPIKey = "search_api_key"

    // Pulse AI proxy session JWT (exchanged from the Apple identity token)
    case proxySessionToken = "proxy_session_token"

    // User password (for in-app Face ID reveal)
    case userPassword = "user_account_password"

    var securityLevel: KeychainSecurityLevel {
        switch self {
        case .userPassword:
            return .requirePasscode
        case .cognitoAccessToken, .cognitoIdToken:
            return .requirePasscode
        case .cognitoRefreshToken:
            return .requirePasscode
        case .cognitoTokenExpiry, .cognitoUserId, .cognitoUserEmail, .cognitoUserName:
            return .standard
        case .apiEndpoint, .stripeCustomerId:
            return .standard
        case .geminiAPIKey:
            return .standard
        case .anthropicAPIKey:
            return .standard
        case .deepSeekAPIKey:
            return .standard
        case .searchAPIKey:
            return .standard
        case .proxySessionToken:
            return .standard
        }
    }
}

// MARK: - Keychain Manager

final class KeychainManager: @unchecked Sendable {
    static let shared = KeychainManager()

    private let serviceName = "com.shimondeitel.pulse"
    private let accessGroup: String? = nil // Set for app group sharing if needed
    private let queue = DispatchQueue(label: "com.shimondeitel.pulse.keychain", qos: .userInitiated)

    private init() {}

    // MARK: - Save

    @discardableResult
    func save(key: KeychainKey, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    @discardableResult
    func save(key: KeychainKey, data: Data) -> Bool {
        queue.sync {
            // Delete existing first
            let deleteQuery = baseQuery(for: key)
            SecItemDelete(deleteQuery as CFDictionary)

            // Build add query with security level
            var addQuery = baseQuery(for: key)
            addQuery[kSecValueData as String] = data

            // Set accessibility based on security level
            switch key.securityLevel {
            case .standard:
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .requirePasscode:
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            case .biometricOrPasscode:
                if let accessControl = SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                    .userPresence,
                    nil
                ) {
                    addQuery[kSecAttrAccessControl as String] = accessControl
                } else {
                    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
                }
            }

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status != errSecSuccess {
                print("[Keychain] Save failed for \(key.rawValue): \(status)")
            }
            return status == errSecSuccess
        }
    }

    // MARK: - Retrieve

    func retrieve(key: KeychainKey) -> String? {
        guard let data = retrieveData(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func retrieveData(key: KeychainKey) -> Data? {
        queue.sync {
            var query = baseQuery(for: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            guard status == errSecSuccess else { return nil }
            return result as? Data
        }
    }

    // MARK: - Delete

    @discardableResult
    func delete(key: KeychainKey) -> Bool {
        queue.sync {
            let query = baseQuery(for: key)
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
    }

    // MARK: - Bulk Operations

    /// Delete all auth-related keys (for sign out)
    func clearAuthTokens() {
        let authKeys: [KeychainKey] = [
            .cognitoAccessToken,
            .cognitoRefreshToken,
            .cognitoIdToken,
            .cognitoTokenExpiry,
            .cognitoUserId,
            .cognitoUserEmail,
            .cognitoUserName,
            .stripeCustomerId,
            .proxySessionToken
        ]
        for key in authKeys {
            delete(key: key)
        }
    }

    /// Delete everything (factory reset)
    func clearAll() {
        for key in KeychainKey.allCases {
            delete(key: key)
        }
    }

    /// Check if a key exists without retrieving value
    func exists(key: KeychainKey) -> Bool {
        queue.sync {
            var query = baseQuery(for: key)
            query[kSecReturnData as String] = false

            let status = SecItemCopyMatching(query as CFDictionary, nil)
            return status == errSecSuccess
        }
    }

    // MARK: - Token Expiry Helpers

    func saveTokenExpiry(_ date: Date) {
        let timestamp = String(date.timeIntervalSince1970)
        save(key: .cognitoTokenExpiry, value: timestamp)
    }

    func getTokenExpiry() -> Date? {
        guard let str = retrieve(key: .cognitoTokenExpiry),
              let interval = TimeInterval(str) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    var isAccessTokenExpired: Bool {
        guard let expiry = getTokenExpiry() else { return true }
        // Consider expired 60 seconds early to account for clock skew
        return Date().addingTimeInterval(60) >= expiry
    }

    // MARK: - Private

    private func baseQuery(for key: KeychainKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}
