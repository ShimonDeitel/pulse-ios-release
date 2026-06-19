import SwiftUI

enum GoalCategory: String, CaseIterable, Identifiable {
    case fitness = "fitness"
    case learning = "learning"
    case finance = "finance"
    case career = "career"
    case health = "health"
    case creative = "creative"
    case social = "social"
    case mindfulness = "mindfulness"
    case personal = "personal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fitness: return "Fitness".localized
        case .learning: return "Learning".localized
        case .finance: return "Finance".localized
        case .career: return "Career".localized
        case .health: return "Health".localized
        case .creative: return "Creative".localized
        case .social: return "Social".localized
        case .mindfulness: return "Mindfulness".localized
        case .personal: return "Personal".localized
        }
    }

    var iconName: String {
        switch self {
        case .fitness: return "figure.run"
        case .learning: return "book.fill"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .career: return "briefcase.fill"
        case .health: return "heart.fill"
        case .creative: return "paintbrush.fill"
        case .social: return "person.2.fill"
        case .mindfulness: return "brain.head.profile"
        case .personal: return "star.fill"
        }
    }

    var color: Color {
        // All categories use signal red — differentiated by icon, not color
        PulseColors.signal
    }
}
