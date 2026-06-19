import Foundation
import CoreData

/// A lightweight "you started creating a goal but didn't finish" record.
///
/// Stored device-locally (UserDefaults) — it is transient creation state, not
/// user content, so it does not belong in CloudKit. A draft appears under the
/// Drafts section in the Goals tab; tapping it re-opens that goal type's
/// creation flow so you can finish. A draft auto-clears once a goal of that
/// type is actually created (see `reconcile`), or when you delete it.
struct GoalDraft: Codable, Identifiable, Hashable {
    let id: UUID
    let typeRaw: String
    let startedAt: Date
}

@Observable
final class DraftService {
    static let shared = DraftService()

    private let key = "pulse_goal_drafts"
    private(set) var drafts: [GoalDraft] = []

    private init() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([GoalDraft].self, from: data) {
            drafts = decoded.sorted { $0.startedAt > $1.startedAt }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Record that the user began creating a goal of `type`. One draft per type
    /// — re-starting the same type just refreshes its timestamp.
    func start(_ type: GoalType) {
        drafts.removeAll { $0.typeRaw == type.rawValue }
        drafts.insert(GoalDraft(id: UUID(), typeRaw: type.rawValue, startedAt: Date()), at: 0)
        persist()
    }

    func remove(_ id: UUID) {
        // Drop any saved photos + scalar fields for this draft's type before
        // removing the record.
        if let d = drafts.first(where: { $0.id == id }), let t = GoalType(rawValue: d.typeRaw) {
            clearDraftPhotos(t)
            clearDraftFields(t)
        }
        drafts.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Draft fields (small scalar creation state)
    //
    // Beyond photos, some flows carry a few scalar inputs the user shouldn't lose
    // if they back out before finishing — for Transformation: target weeks, current
    // weight + unit, and training style. Stored as a tiny JSON blob in UserDefaults
    // keyed by goal type (one draft per type). Restored when the flow re-opens;
    // cleared when the goal is actually created or the draft is deleted.
    private func draftFieldsKey(_ type: GoalType) -> String { "pulse_draft_fields_\(type.rawValue)" }

    /// Save the in-progress scalar inputs for a draft of `type`.
    func saveDraftFields(_ type: GoalType, _ fields: [String: String]) {
        if let data = try? JSONEncoder().encode(fields) {
            UserDefaults.standard.set(data, forKey: draftFieldsKey(type))
        }
    }

    /// The saved scalar inputs for a draft of `type`, or empty if none.
    func draftFields(_ type: GoalType) -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: draftFieldsKey(type)),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    func clearDraftFields(_ type: GoalType) {
        UserDefaults.standard.removeObject(forKey: draftFieldsKey(type))
    }

    // MARK: - Draft photos (e.g. Transformation before/after)
    //
    // Photos picked before a goal is finished are too large for UserDefaults and
    // are transient creation state, so they live as files in Caches keyed by goal
    // type (one draft per type). Restored when that creation flow re-opens; cleared
    // when the goal is actually created or the draft is deleted.
    private var draftPhotosDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoalDraftPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func draftPhotoURL(_ type: GoalType, _ slot: String) -> URL {
        draftPhotosDir.appendingPathComponent("\(type.rawValue)-\(slot).jpg")
    }

    /// Save (or, when nil, clear) the in-progress before/after photos for a draft.
    func saveDraftPhotos(_ type: GoalType, current: Data?, goal: Data?) {
        writeDraftPhoto(current, to: draftPhotoURL(type, "current"))
        writeDraftPhoto(goal, to: draftPhotoURL(type, "goal"))
    }

    /// The saved before/after photos for a draft of `type`, if any.
    func draftPhotos(_ type: GoalType) -> (current: Data?, goal: Data?) {
        (try? Data(contentsOf: draftPhotoURL(type, "current")),
         try? Data(contentsOf: draftPhotoURL(type, "goal")))
    }

    func clearDraftPhotos(_ type: GoalType) {
        try? FileManager.default.removeItem(at: draftPhotoURL(type, "current"))
        try? FileManager.default.removeItem(at: draftPhotoURL(type, "goal"))
    }

    private func writeDraftPhoto(_ data: Data?, to url: URL) {
        if let data { try? data.write(to: url, options: .atomic) }
        else { try? FileManager.default.removeItem(at: url) }
    }

    /// Drop drafts that have since become real goals. Creation flows tag goals
    /// with a different category taxonomy (finance/career/learning…) than the
    /// GoalType, so we match by TIME instead: a goal created at/after a draft was
    /// started is the goal that draft turned into. Greedy newest-first matching
    /// so each created goal consumes at most one draft (a still-unfinished older
    /// draft survives). Called when the Goals list appears/refreshes.
    func reconcile(against goals: [Goal]) {
        guard !drafts.isEmpty else { return }
        var availableGoalDates = goals.compactMap { $0.createdAt }.sorted(by: >)  // newest first
        var survivors: [GoalDraft] = []
        for draft in drafts.sorted(by: { $0.startedAt > $1.startedAt }) {          // newest draft first
            if let idx = availableGoalDates.lastIndex(where: { $0 >= draft.startedAt }) {
                availableGoalDates.remove(at: idx)   // this goal claims (consumes) the draft
                // The draft became a real goal — drop its cached photos + scalar
                // fields so they don't orphan (mirrors remove(_:)).
                if let t = GoalType(rawValue: draft.typeRaw) {
                    clearDraftPhotos(t)
                    clearDraftFields(t)
                }
            } else {
                survivors.append(draft)
            }
        }
        if survivors.count != drafts.count {
            drafts = survivors.sorted { $0.startedAt > $1.startedAt }
            persist()
        }
    }
}
