import Foundation

enum GoalStatus: String, CaseIterable {
    case active = "active"
    case paused = "paused"
    case completed = "completed"
    case abandoned = "abandoned"

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        }
    }
}
