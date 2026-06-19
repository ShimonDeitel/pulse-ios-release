import SwiftUI

/// Shown when the user taps "Example" on an exercise row. Pulls AI-generated
/// form cues + opens a YouTube search for a real video.
struct ExerciseExampleSheet: View {
    let exercise: WorkoutExercise
    @Environment(\.dismiss) private var dismiss
    @State private var formCues: String = ""
    @State private var loading: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    quickRefCard
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.85)
                            Text("Loading form notes…")
                                .font(.system(size: 13))
                                .foregroundColor(PulseColors.muted)
                        }
                        .padding(.vertical, 12)
                    } else if !formCues.isEmpty {
                        formCuesCard
                    }
                    videoLink
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.vertical, 16)
            }
            .pulseScreen()
            .navigationTitle("Form example")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadFormCues() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.signal)
            Text(exercise.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(PulseColors.ink)
            Text("\(exercise.sets) sets · \(exercise.reps) · rest \(exercise.restSeconds)s")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(PulseColors.muted)
        }
    }

    private var quickRefCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK REFERENCE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.muted)
            if let note = exercise.notes, !note.isEmpty {
                Text(note)
                    .font(.system(size: 14))
                    .foregroundColor(PulseColors.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap below for AI-generated form cues, then watch a video to see it done.")
                    .font(.system(size: 13))
                    .foregroundColor(PulseColors.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var formCuesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW TO DO IT")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(PulseColors.signal)
            Text(formCues)
                .font(.system(size: 14))
                .foregroundColor(PulseColors.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var videoLink: some View {
        let query = exercise.name
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://www.youtube.com/results?search_query=\(query)+proper+form")!
        return Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Watch a real video")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(PulseColors.signal)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func loadFormCues() async {
        let prompt = """
        Explain how to do "\(exercise.name)" with perfect form. Cover:
        1. Starting position (foot placement, grip, body alignment)
        2. The movement itself, step by step (tempo, breathing)
        3. The 3 most common mistakes beginners make
        4. One simple cue to remember

        Keep it tight — 5 to 8 short sentences. No emojis. No fluff.
        """
        do {
            let response = try await AIRouter.shared.sendMessage(
                userMessage: prompt,
                systemPrompt: "You are a certified strength coach. Explain exercises clearly with concrete cues. Never use emojis." + LocalizationManager.shared.aiLanguageInstruction,
                temperature: 0.4,
                maxTokens: 500
            )
            formCues = response
        } catch {
            formCues = "Couldn't load form notes — check the video link below."
        }
        loading = false
    }
}
