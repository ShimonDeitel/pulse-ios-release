import Foundation

// MARK: - API Error

enum APIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)
    case noResponse
    case rateLimited
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API not configured. All AI calls route through the server."
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
        case .serverError(let code, _): return "Server error (\(code)). Please try again."
        case .noResponse: return "No response from server"
        case .rateLimited: return "Rate limited. Please try again later."
        case .unauthorized: return "Unauthorized. Please sign in again."
        }
    }
}

// MARK: - Generic HTTP Client

/// A small async URLSession wrapper used for ad-hoc HTTP calls (e.g. AI provider
/// REST endpoints). The app no longer runs its own backend: private data syncs
/// via CloudKit (`PersistenceController`) and auth is native Sign in with Apple,
/// so there is no app server to route requests through.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    private let session: URLSession
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 1.0

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120

        #if DEBUG
        self.session = URLSession.pinnedSession(configuration: config, enforce: false)
        #else
        self.session = URLSession.pinnedSession(configuration: config, enforce: true)
        #endif
    }

    func post<T: Decodable>(url: URL, body: Data, headers: [String: String] = [:]) async throws -> T {
        // Basic rate limiting
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            try await Task.sleep(nanoseconds: UInt64((minRequestInterval - elapsed) * 1_000_000_000))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        lastRequestTime = Date()

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noResponse
            }

            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }

            if httpResponse.statusCode == 429 {
                throw APIError.rateLimited
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, errorMsg)
            }

            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                return decoded
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}
