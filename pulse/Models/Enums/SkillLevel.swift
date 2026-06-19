import Foundation
import SwiftUI

enum SkillLevel: String, CaseIterable, Identifiable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    case expert = "expert"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner".localized
        case .intermediate: return "Intermediate".localized
        case .advanced: return "Advanced".localized
        case .expert: return "Expert".localized
        }
    }
}

enum UrgencyLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .low: return PulseColors.success
        case .medium: return PulseColors.warning
        case .high: return PulseColors.danger
        case .critical: return PulseColors.danger
        }
    }
}

enum VerificationType: String, CaseIterable {
    case manual = "manual"
    case photo = "photo"
    case quiz = "quiz"
    case financial = "financial"

    var displayName: String { rawValue.capitalized }
}
