import Foundation
import UIKit

/// Finds the best explainer video for a pulse and opens it.
///
/// The button that calls this must ALWAYS do something (Pulse rule: no dead
/// buttons), so resolution degrades gracefully:
///
///   1. Pro/Max with a search key configured: ask the web search for the best
///      match and, if it returns a concrete *playable* video, open THAT video
///      directly (YouTube app when installed, otherwise the web player). This is
///      the literal "find the best video on the internet and open it" path.
///   2. Otherwise (Free tier, or no search key, or no video in the results):
///      open a YouTube search for the pulse so the user still lands right on the
///      best-matching explainer videos — and at zero API cost.
///
/// No API keys ever live in the app — web search goes through WebSearchService,
/// which holds the search key in the Keychain. (Pulse security mandate.)
@MainActor
enum PulseVideoService {

    /// A focused how-to query: the pulse, framed by its goal.
    static func searchQuery(pulseTitle: String, goalTitle: String?) -> String {
        let pulse = pulseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal  = (goalTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if pulse.isEmpty { return "how to \(goal) step by step tutorial" }
        let base  = goal.isEmpty ? "how to \(pulse)" : "how to \(pulse) for \(goal)"
        return "\(base) step by step tutorial"
    }

    /// Find the best explainer video for a pulse and open it. ALWAYS opens
    /// something: a specific video when one can be resolved, else YouTube search.
    static func findAndOpen(pulseTitle: String, goalTitle: String?) async {
        let query = searchQuery(pulseTitle: pulseTitle, goalTitle: goalTitle)

        // Only spend a paid search credit for users who have AI (Pro/Max) AND a
        // configured search key. Everyone else gets the free YouTube-search path.
        let canResolve = SubscriptionManager.shared.hasAIGeneration
            && WebSearchService.shared.isConfigured

        if canResolve, let video = await bestVideoURL(for: query) {
            await open(video)
        } else {
            openYouTubeSearch(query)
        }
    }

    // MARK: - Resolution

    /// Top playable video URL for a query, or nil if search is off / errors / no
    /// video appears in the results. WebSearchService returns a formatted text
    /// block ("Sources:\n1. title\nURL\nsnippet…"); we scan it for the first URL
    /// that points at a single watchable video.
    static func bestVideoURL(for query: String) async -> URL? {
        guard let block = try? await WebSearchService.shared.search(
            query: query + " video", maxResults: 8
        ) else { return nil }

        let separators = CharacterSet(charactersIn: " \n\t")
        for raw in block.components(separatedBy: separators) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "()[]<>,\"'."))
            guard token.lowercased().hasPrefix("http") else { continue }
            if let video = playableVideoURL(from: token) { return video }
        }
        return nil
    }

    /// Accept only URLs that point at a single watchable video — not a channel,
    /// playlist, or search page.
    static func playableVideoURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        switch host {
        case "youtube.com", "m.youtube.com":
            let hasVideoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains { $0.name == "v" && !($0.value ?? "").isEmpty } ?? false
            if url.path == "/watch", hasVideoID { return url }
            if url.path.hasPrefix("/shorts/"), url.pathComponents.count >= 3 { return url }
            return nil
        case "youtu.be":
            return url.pathComponents.count >= 2 ? url : nil
        case "vimeo.com":
            if let first = url.pathComponents.dropFirst().first, Int(first) != nil { return url }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Opening

    /// Open a resolved video — YouTube app deep link when possible, else web.
    static func open(_ url: URL) async {
        if let appURL = youtubeAppURL(for: url) {
            let opened = await openURL(appURL)
            if !opened { _ = await openURL(url) }
        } else {
            _ = await openURL(url)
        }
    }

    /// Open a YouTube search results page (app, falling back to web).
    static func openYouTubeSearch(_ query: String) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let webURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)")!
        if let appURL = URL(string: "youtube://results?search_query=\(encoded)") {
            UIApplication.shared.open(appURL, options: [:]) { ok in
                if !ok { UIApplication.shared.open(webURL) }
            }
        } else {
            UIApplication.shared.open(webURL)
        }
    }

    /// Map a watch / youtu.be / shorts URL to the `youtube://` app deep link.
    static func youtubeAppURL(for url: URL) -> URL? {
        guard let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        var videoID: String?
        switch host {
        case "youtu.be":
            videoID = url.pathComponents.dropFirst().first
        case "youtube.com", "m.youtube.com":
            if url.path == "/watch" {
                videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if url.path.hasPrefix("/shorts/") {
                videoID = url.pathComponents.dropFirst(2).first
            }
        default:
            return nil
        }
        guard let id = videoID, !id.isEmpty else { return nil }
        return URL(string: "youtube://watch?v=\(id)")
    }

    @discardableResult
    private static func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { cont in
            UIApplication.shared.open(url, options: [:]) { ok in cont.resume(returning: ok) }
        }
    }
}
