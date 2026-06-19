import SwiftUI
import UIKit
import Combine

// MARK: - Store
//
// Lightweight per-user personalization store. The community/social feed was
// removed in v1, so this now holds only the three things the rest of the app
// still needs, all persisted locally under Documents/social/:
//   • the user's profile picture (Documents/social/images/<uuid>.jpg)
//   • an optional Instagram-style "note" (24h), stored in profile_meta.json
//   • the user's Saved Quotes (saved_quotes.json)
//
// On-disk paths/keys are kept identical to the previous version so existing
// users keep their photo and saved quotes after upgrading.

@MainActor
final class SocialStore: ObservableObject {
    static let shared = SocialStore()

    @Published private(set) var savedQuotes: [String] = []

    /// The max length of a profile note (Instagram-style thought bubble).
    static let noteMaxLength = 60
    /// The current user's profile picture filename + optional "note".
    @Published private(set) var profileImageName: String? = nil
    @Published private(set) var note: String? = nil
    @Published private(set) var noteCreatedAt: Date? = nil
    private var cachedProfileImage: UIImage?

    private let dir: URL
    private let imagesDir: URL
    private let savedQuotesURL: URL
    private let profileMetaURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("social", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        savedQuotesURL = dir.appendingPathComponent("saved_quotes.json")
        profileMetaURL = dir.appendingPathComponent("profile_meta.json")
        load()
    }

    // MARK: Persistence

    private func load() {
        if let d = try? Data(contentsOf: savedQuotesURL),
           let q = try? JSONDecoder().decode([String].self, from: d) {
            savedQuotes = q
        }
        if let d = try? Data(contentsOf: profileMetaURL),
           let m = try? JSONDecoder().decode(ProfileMeta.self, from: d) {
            profileImageName = m.imageFile
            // Notes expire after 24h, like Instagram.
            if let n = m.note, let at = m.noteAt, Date().timeIntervalSince(at) < 86_400 {
                note = n; noteCreatedAt = at
            }
        }
    }

    private func saveSavedQuotes() { try? JSONEncoder().encode(savedQuotes).write(to: savedQuotesURL) }
    private func saveProfileMeta() {
        let m = ProfileMeta(imageFile: profileImageName, note: note, noteAt: noteCreatedAt)
        try? JSONEncoder().encode(m).write(to: profileMetaURL)
    }

    // MARK: Images

    private func loadImage(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: imagesDir.appendingPathComponent(name).path)
    }

    private func persistImage(_ image: UIImage) -> String? {
        let resized = image.socialDownscaled(maxDimension: 1280)
        guard let data = resized.jpegData(compressionQuality: 0.72) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: imagesDir.appendingPathComponent(name))
            return name
        } catch { return nil }
    }

    // MARK: Saved quotes

    func isQuoteSaved(_ q: String) -> Bool { savedQuotes.contains(q) }

    func saveQuote(_ q: String) {
        guard !savedQuotes.contains(q) else { return }
        savedQuotes.insert(q, at: 0)
        saveSavedQuotes()
    }

    func unsaveQuote(_ q: String) {
        savedQuotes.removeAll { $0 == q }
        saveSavedQuotes()
    }

    func toggleSaveQuote(_ q: String) {
        if isQuoteSaved(q) { unsaveQuote(q) } else { saveQuote(q) }
    }

    // MARK: Profile picture

    func profileImage() -> UIImage? {
        if cachedProfileImage == nil, let name = profileImageName {
            cachedProfileImage = loadImage(name)
        }
        return cachedProfileImage
    }

    func setProfileImage(_ image: UIImage) {
        if let old = profileImageName {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(old))
        }
        cachedProfileImage = nil
        profileImageName = persistImage(image)
        saveProfileMeta()
    }

    func removeProfileImage() {
        if let old = profileImageName {
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(old))
        }
        cachedProfileImage = nil
        profileImageName = nil
        saveProfileMeta()
    }

    // MARK: Note (Instagram-style thought, 24h)

    /// The note if it exists and hasn't expired.
    var activeNote: String? {
        guard let note, let at = noteCreatedAt, Date().timeIntervalSince(at) < 86_400 else { return nil }
        return note
    }

    func setNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { clearNote(); return }
        note = String(t.prefix(Self.noteMaxLength))
        noteCreatedAt = Date()
        saveProfileMeta()
    }

    func clearNote() {
        note = nil
        noteCreatedAt = nil
        saveProfileMeta()
    }
}

private struct ProfileMeta: Codable {
    var imageFile: String?
    var note: String?
    var noteAt: Date?
}

extension UIImage {
    /// Downscale so the longest side is at most `maxDimension`, preserving aspect.
    func socialDownscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
