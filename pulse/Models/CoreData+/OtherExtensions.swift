import Foundation
import CoreData

extension Milestone {
    var titleValue: String {
        get { title ?? "Milestone" }
        set { title = newValue }
    }
}

extension DailyTask {
    var titleValue: String {
        get { title ?? "Task" }
        set { title = newValue }
    }

    var howTo: String {
        get { howToDescription ?? "" }
        set { howToDescription = newValue }
    }

    var proofRequired: String {
        get { proofDescription ?? "" }
        set { proofDescription = newValue }
    }

    var proofTypeValue: String {
        get { proofType ?? "text" }
        set { proofType = newValue }
    }

    var verificationStatusValue: String {
        get { verificationStatus ?? "pending" }
        set { verificationStatus = newValue }
    }

    var isPending: Bool { verificationStatusValue == "pending" }
    var isVerified: Bool { verificationStatusValue == "verified" }
    var isRejected: Bool { verificationStatusValue == "rejected" }
    var isSubmitted: Bool { verificationStatusValue == "submitted" }
}

extension MentorMessage {
    var contentValue: String {
        get { content ?? "" }
        set { content = newValue }
    }

    var personalityEnum: MentorPersonality {
        MentorPersonality(rawValue: personality ?? "coach") ?? .coach
    }
}

extension Achievement {
    var titleValue: String {
        get { title ?? "Achievement" }
        set { title = newValue }
    }

    var descriptionValue: String {
        get { achievementDescription ?? "" }
        set { achievementDescription = newValue }
    }
}

extension FocusSession {
    var durationString: String {
        let minutes = Int(actualDurationMinutes)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
