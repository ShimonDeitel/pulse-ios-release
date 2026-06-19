import Foundation

/// Tracks which goals were built using AI (a Pro/Max feature). If the user
/// later downgrades to Free, these goals are locked — opening one prompts an
/// upgrade rather than exposing paid AI content for free.
enum ProGoalRegistry {
    private static let key = "pulse_pro_goal_ids"

    static func mark(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        set.insert(id)
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    static func isPro(_ id: String?) -> Bool {
        guard let id, !id.isEmpty else { return false }
        return Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id)
    }

    static func clear(_ id: String?) {
        guard let id else { return }
        var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        set.remove(id)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
