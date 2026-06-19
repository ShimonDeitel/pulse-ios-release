import Foundation
import CommonCrypto
import CryptoKit

// MARK: - Certificate Pinning Configuration

/// Public key pins for TLS certificate pinning.
/// Update these when rotating server certificates.
struct PinningConfiguration {
    /// SHA-256 hashes of the Subject Public Key Info (SPKI) for pinned certificates.
    /// Include at least 2: primary + backup to avoid lockout during rotation.
    static let pins: [String: [String]] = [
        // AWS API Gateway (us-east-1) — update these with actual SPKI hashes after deployment
        "execute-api.us-east-1.amazonaws.com": [
            // Primary: Amazon RSA 2048 M02
            // Backup: Amazon RSA 2048 M03
            // These are placeholder pins — replace with actual SPKI hashes from your deployment
        ],
        // Cognito
        "cognito-idp.us-east-1.amazonaws.com": [
            // Amazon root CA pins
        ]
    ]

    /// Domains that require pinning. Requests to unpinned domains are allowed
    /// but logged for monitoring.
    static let pinnedDomains: Set<String> = [
        "execute-api.us-east-1.amazonaws.com",
        "cognito-idp.us-east-1.amazonaws.com"
    ]

    /// How long to cache pin validation results (seconds)
    static let cacheTimeout: TimeInterval = 300
}

// MARK: - Pinning Session Delegate

/// URLSessionDelegate that enforces TLS public key pinning.
/// Attach to any URLSession that communicates with Pulse backend services.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let pinnedHashes: [String: Set<String>]
    private let enforcePinning: Bool

    /// - Parameters:
    ///   - pins: Domain -> [SPKI SHA-256 hash base64] mapping
    ///   - enforce: If true, fails connections with invalid pins. If false, logs but allows (for testing).
    init(pins: [String: [String]] = PinningConfiguration.pins, enforce: Bool = true) {
        self.pinnedHashes = pins.mapValues { Set($0) }
        self.enforcePinning = enforce
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // If this domain doesn't require pinning, use default handling
        guard let expectedHashes = pinnedHashes[host], !expectedHashes.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust
        var error: CFError?
        let isServerTrusted = SecTrustEvaluateWithError(serverTrust, &error)

        guard isServerTrusted else {
            print("[CertPin] Server trust evaluation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract and validate public key pins from the certificate chain
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var pinMatched = false

        for certificate in certificateChain {
            // Get the public key from the certificate
            guard let publicKey = SecCertificateCopyKey(certificate) else {
                continue
            }

            // Get the public key data
            guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
                continue
            }

            // Hash the public key (SPKI)
            let hash = SHA256.hash(data: publicKeyData)
            let hashBase64 = Data(hash).base64EncodedString()

            if expectedHashes.contains(hashBase64) {
                pinMatched = true
                break
            }
        }

        if pinMatched {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else if !enforcePinning {
            // Development mode: log but allow
            print("[CertPin] WARNING: Pin mismatch for \(host) — allowing in non-enforce mode")
            completionHandler(.performDefaultHandling, nil)
        } else {
            print("[CertPin] BLOCKED: Certificate pin mismatch for \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Pinned URLSession Factory

extension URLSession {
    /// Create a URLSession with certificate pinning enabled.
    static func pinnedSession(
        configuration: URLSessionConfiguration = .default,
        enforce: Bool = true
    ) -> URLSession {
        let delegate = CertificatePinningDelegate(enforce: enforce)
        return URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}
