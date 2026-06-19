import Foundation
import CoreData

class StepVerificationService {
    static let shared = StepVerificationService()

    func verifyStepCompletion(
        step: DailyTask,
        proofText: String,
        context: NSManagedObjectContext
    ) async -> (verified: Bool, feedback: String) {
        let goalTitle = step.goal?.titleValue ?? "Unknown"
        let stepTitle = step.titleValue
        let proofRequired = step.proofRequired
        let howTo = step.howTo

        let prompt = """
        You are verifying whether a user completed a step in their goal roadmap.

        Goal: \(goalTitle)
        Step #\(step.stepNumber): \(stepTitle)
        How to do it: \(howTo)
        Required proof: \(proofRequired)

        User's proof/evidence: \(proofText)

        Analyze whether the user has genuinely completed this step based on their proof.
        Be reasonable but thorough. If the proof shows the step was done, approve it.
        If the proof is vague, incomplete, or clearly doesn't match the step, reject it with specific feedback.

        Respond ONLY with this JSON:
        {
            "verified": true/false,
            "feedback": "<1-2 sentence feedback explaining your decision>",
            "tips": "<optional helpful tip for the next step>"
        }
        """

        do {
            let response = try await GeminiAPIService.shared.sendMessageJSON(
                userMessage: prompt,
                systemPrompt: "You are Pulse's step verification AI. Be fair but ensure users actually complete each step. Respond in valid JSON only.",
                temperature: 0.3,
                maxTokens: 512
            )

            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let verified = json["verified"] as? Bool ?? false
                let feedback = json["feedback"] as? String ?? "Verification complete."
                return (verified, feedback)
            }
            return (false, "Could not parse verification response. Please try again.")
        } catch {
            return (false, "Verification error: \(error.localizedDescription)")
        }
    }

    func verifyWithPhoto(
        step: DailyTask,
        photoData: Data,
        proofText: String,
        context: NSManagedObjectContext
    ) async -> (verified: Bool, feedback: String) {
        let goalTitle = step.goal?.titleValue ?? "Unknown"
        let stepTitle = step.titleValue
        let proofRequired = step.proofRequired

        let prompt = """
        You are verifying whether a user completed a step in their goal roadmap using a photo they submitted.

        Goal: \(goalTitle)
        Step #\(step.stepNumber): \(stepTitle)
        Required proof: \(proofRequired)
        User's notes: \(proofText)

        Look at the photo and determine if it shows the step was completed.
        Be reasonable — the photo should show evidence related to the step.

        Respond ONLY with this JSON:
        {
            "verified": true/false,
            "feedback": "<1-2 sentence feedback explaining your decision>"
        }
        """

        do {
            let response = try await GeminiAPIService.shared.sendVisionMessage(
                textPrompt: prompt,
                images: [(data: photoData, mimeType: "image/jpeg")],
                systemPrompt: "You are Pulse's step verification AI with vision. Analyze the photo to verify step completion. Respond in valid JSON only.",
                temperature: 0.3,
                maxTokens: 512
            )

            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let verified = json["verified"] as? Bool ?? false
                let feedback = json["feedback"] as? String ?? "Verification complete."
                return (verified, feedback)
            }
            return (false, "Could not parse verification response.")
        } catch {
            return (false, "Verification error: \(error.localizedDescription)")
        }
    }
}
