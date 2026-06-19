import SwiftUI
import CoreData
import PhotosUI

struct RoadmapView: View {
    @ObservedObject var goal: Goal
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedStep: DailyTask?
    @State private var showingProofSheet = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    roadmapHeader
                    progressBar
                    stepsList
                }
                .padding(.bottom, PulseSpacing.section)
            }
            .onAppear {
                if let nextStep = goal.nextStep {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(PulseAnimations.standard) {
                            proxy.scrollTo("step-\(nextStep.stepNumber)", anchor: .center)
                        }
                    }
                }
            }
        }
        .pulseScreen()
        .navigationTitle("Roadmap")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProofSheet) {
            if let step = selectedStep {
                StepProofSheet(step: step, goal: goal)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    private var roadmapHeader: some View {
        HStack(spacing: PulseSpacing.lg) {
            Image(systemName: goal.categoryEnum.iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(goal.categoryEnum.color)
                .frame(width: 48, height: 48)
                .background(goal.categoryEnum.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: M3Shapes.medium, style: .continuous))

            VStack(alignment: .leading, spacing: PulseSpacing.xs) {
                Text(goal.titleValue)
                    .font(PulseTypography.titleMedium)
                    .foregroundColor(PulseColors.textPrimary)
                Text("\(goal.completedSteps) of \(goal.totalSteps) " + "pulses complete".localized)
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textSecondary)
            }

            Spacer()

            Text("\(Int(Double(goal.completedSteps) / Double(max(goal.totalSteps, 1)) * 100))%")
                .font(PulseTypography.monoLarge)
                .foregroundColor(PulseColors.primary)
        }
        .padding(PulseSpacing.cardPadding)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, PulseSpacing.lg)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(PulseColors.surfaceContainer)
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 3)
                    .fill(goal.categoryEnum.color)
                    .frame(width: geo.size.width * Double(goal.completedSteps) / Double(max(goal.totalSteps, 1)), height: 4)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, PulseSpacing.screenEdge)
        .padding(.top, PulseSpacing.lg)
        .padding(.bottom, PulseSpacing.sm)
    }

    private var stepsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(goal.allSteps, id: \.objectID) { step in
                StepRow(
                    step: step,
                    isCurrentStep: step.stepNumber == Int32(goal.currentStepIndex + 1),
                    totalSteps: goal.totalSteps,
                    onSubmitProof: {
                        selectedStep = step
                        showingProofSheet = true
                    }
                )
                .id("step-\(step.stepNumber)")
            }
        }
    }
}

struct StepRow: View {
    @ObservedObject var step: DailyTask
    let isCurrentStep: Bool
    let totalSteps: Int
    let onSubmitProof: () -> Void

    var statusColor: Color {
        if step.isCompleted { return PulseColors.success }
        if step.isRejected { return PulseColors.danger }
        if step.isSubmitted { return PulseColors.warning }
        if isCurrentStep { return PulseColors.primary }
        return PulseColors.textTertiary
    }

    var statusIcon: String {
        if step.isCompleted { return "checkmark.circle.fill" }
        if step.isRejected { return "xmark.circle.fill" }
        if step.isSubmitted { return "clock.fill" }
        if isCurrentStep { return "arrow.right.circle.fill" }
        return "circle"
    }

    var body: some View {
        HStack(alignment: .top, spacing: PulseSpacing.lg) {
            // Timeline rail
            VStack(spacing: 0) {
                if step.stepNumber > 1 {
                    Rectangle()
                        .fill(step.isCompleted ? PulseColors.success.opacity(0.3) : PulseColors.surfaceContainer)
                        .frame(width: 2, height: PulseSpacing.lg)
                } else {
                    Spacer().frame(height: PulseSpacing.lg)
                }

                ZStack {
                    Circle()
                        .fill(statusColor.opacity(isCurrentStep ? 0.15 : 0.08))
                        .frame(width: 36, height: 36)

                    if isCurrentStep {
                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                    }

                    Image(systemName: statusIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(statusColor)
                }

                if step.stepNumber < Int32(totalSteps) {
                    Rectangle()
                        .fill(step.isCompleted ? PulseColors.success.opacity(0.3) : PulseColors.surfaceContainer)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            // Step content
            VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                HStack {
                    Text("PULSE \(String(format: "%02d", step.stepNumber))")
                        .font(PulseTypography.eyebrow)
                        .foregroundColor(statusColor)
                        .eyebrowTracking()

                    if step.isHighPriority {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(PulseColors.warning)
                    }

                    Spacer()

                    if step.estimatedMinutes > 0 {
                        HStack(spacing: PulseSpacing.xxs) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("\(step.estimatedMinutes)m")
                                .font(PulseTypography.monoCaption)
                        }
                        .foregroundColor(PulseColors.textTertiary)
                    }
                }

                Text(step.titleValue)
                    .font(PulseTypography.labelLargeEmphasized)
                    .foregroundColor(step.isCompleted ? PulseColors.textSecondary : PulseColors.textPrimary)
                    .strikethrough(step.isCompleted)

                if isCurrentStep || step.isRejected {
                    if !step.howTo.isEmpty {
                        VStack(alignment: .leading, spacing: PulseSpacing.xs) {
                            HStack(spacing: PulseSpacing.xs) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(PulseColors.warning)
                                Text("How to do it:")
                                    .font(PulseTypography.labelSmall)
                                    .foregroundColor(PulseColors.warning)
                            }
                            Text(step.howTo)
                                .font(PulseTypography.bodySmall)
                                .foregroundColor(PulseColors.textSecondary)
                                .lineSpacing(3)
                        }
                        .padding(PulseSpacing.md)
                        .background(PulseColors.warning.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: M3Shapes.medium, style: .continuous))
                    }

                    if !step.proofRequired.isEmpty {
                        HStack(spacing: PulseSpacing.xs) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(PulseColors.secondary)
                            Text("Proof needed: \(step.proofRequired)")
                                .font(PulseTypography.labelSmall)
                                .foregroundColor(PulseColors.secondary)
                        }
                    }

                    if !step.isCompleted {
                        Button(action: onSubmitProof) {
                            HStack(spacing: PulseSpacing.xs) {
                                Image(systemName: step.isRejected ? "arrow.counterclockwise" : "square.and.arrow.up.fill")
                                    .font(.system(size: 13))
                                Text(step.isRejected ? "Resubmit Proof" : "Submit Proof")
                                    .font(PulseTypography.labelLargeEmphasized)
                            }
                            .foregroundColor(PulseColors.onPrimary)
                            .padding(.horizontal, PulseSpacing.xl)
                            .padding(.vertical, PulseSpacing.sm + 2)
                            .background(PulseColors.primary)
                            .clipShape(Capsule())
                        }
                    }
                }

                if step.isRejected, let response = step.verificationAIResponse {
                    HStack(spacing: PulseSpacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(PulseColors.danger)
                        Text(response)
                            .font(PulseTypography.bodySmall)
                            .foregroundColor(PulseColors.danger)
                    }
                    .padding(PulseSpacing.sm + 2)
                    .background(PulseColors.danger.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: M3Shapes.small, style: .continuous))
                }

                if step.isCompleted, let response = step.verificationAIResponse {
                    HStack(spacing: PulseSpacing.xs) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(PulseColors.success)
                        Text(response)
                            .font(PulseTypography.bodySmall)
                            .foregroundColor(PulseColors.success.opacity(0.8))
                    }
                }
            }
            .padding(.vertical, PulseSpacing.md)
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
        .background(isCurrentStep ? PulseColors.primary.opacity(0.02) : Color.clear)
    }
}

// MARK: - Proof Submission Sheet

struct StepProofSheet: View {
    @ObservedObject var step: DailyTask
    @ObservedObject var goal: Goal
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var proofText = ""
    @State private var isVerifying = false
    @State private var verificationResult: (verified: Bool, feedback: String)?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showingCamera = false

    // MARK: - Proof photo persistence (Caches, no Core Data migration)
    //
    // The proof JPEG is too large for Core Data and is recoverable, so it lives
    // as a file in Caches keyed by the task's stable id. Only the relative
    // filename is stored in the existing `DailyTask.proofSubmission` string, so
    // the photo survives closing and reopening the proof sheet.
    private static var proofPhotosDir: URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Proof", isDirectory: true)
        }
        let dir = caches.appendingPathComponent("Proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Stable filename for this step's proof photo.
    private var proofPhotoFilename: String {
        let key = step.id?.uuidString ?? "step-\(step.stepNumber)"
        return "\(key).jpg"
    }

    /// Write the JPEG to Caches and return the relative filename to store, or nil
    /// if there is no photo to persist.
    private func persistProofPhoto() -> String? {
        guard let photoData else { return nil }
        let filename = proofPhotoFilename
        try? photoData.write(to: Self.proofPhotosDir.appendingPathComponent(filename))
        return filename
    }

    /// Load a previously saved proof photo (if any) referenced by `proofSubmission`.
    private func loadSavedProofPhoto() -> Data? {
        guard let filename = step.proofSubmission, !filename.isEmpty else { return nil }
        return try? Data(contentsOf: Self.proofPhotosDir.appendingPathComponent(filename))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PulseSpacing.xl) {
                    VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                        Text("PULSE \(String(format: "%02d", step.stepNumber))")
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(PulseColors.primary)
                            .eyebrowTracking()
                        Text(step.titleValue)
                            .font(PulseTypography.titleLarge)
                            .foregroundColor(PulseColors.textPrimary)
                    }

                    if !step.howTo.isEmpty {
                        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                            HStack(spacing: PulseSpacing.xs) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(PulseColors.warning)
                                Text("Instructions")
                                    .font(PulseTypography.labelLargeEmphasized)
                                    .foregroundColor(PulseColors.textPrimary)
                            }
                            Text(step.howTo)
                                .font(PulseTypography.bodyMedium)
                                .foregroundColor(PulseColors.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(PulseSpacing.lg)
                        .background(PulseColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                        )
                    }

                    VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                        HStack(spacing: PulseSpacing.xs) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(PulseColors.secondary)
                            Text("Required Proof")
                                .font(PulseTypography.labelLargeEmphasized)
                                .foregroundColor(PulseColors.textPrimary)
                        }
                        Text(step.proofRequired)
                            .font(PulseTypography.bodyMedium)
                            .foregroundColor(PulseColors.textSecondary)
                    }

                    // ── Photo proof — always available, two sources ───
                    // Either pick from Photos or open the Camera. After capture,
                    // show a thumbnail with a Remove option.
                    VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                        Text("PHOTO PROOF (OPTIONAL)".localized)
                            .font(PulseTypography.eyebrow)
                            .eyebrowTracking()
                            .foregroundColor(PulseColors.textTertiary)

                        if let photoData,
                           let uiImage = UIImage(data: photoData) {
                            // Thumbnail + remove
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))

                                Button {
                                    self.photoData = nil
                                    self.selectedPhoto = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                        .padding(8)
                                }
                            }
                        } else {
                            HStack(spacing: 10) {
                                // Photo library picker
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 14))
                                        Text("Choose Photo".localized)
                                    }
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(PulseColors.signal)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(PulseColors.signal.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(PulseColors.signal.opacity(0.35), lineWidth: 1)
                                    )
                                }

                                // Camera capture
                                Button {
                                    showingCamera = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14))
                                        Text("Take Photo".localized)
                                    }
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(PulseColors.signal)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                    .onChange(of: selectedPhoto) {
                        Task {
                            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                photoData = data
                            }
                        }
                    }
                    .sheet(isPresented: $showingCamera) {
                        CameraPicker(imageData: $photoData)
                            .ignoresSafeArea()
                    }

                    VStack(alignment: .leading, spacing: PulseSpacing.sm) {
                        Text("YOUR PROOF")
                            .font(PulseTypography.eyebrow)
                            .foregroundColor(PulseColors.textTertiary)
                            .eyebrowTracking()
                        TextEditor(text: $proofText)
                            .font(PulseTypography.bodyMedium)
                            .foregroundColor(PulseColors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                            .padding(PulseSpacing.lg)
                            .background(PulseColors.surfaceContainer)
                            .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                                    .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
                            )
                    }

                    if let result = verificationResult {
                        HStack(spacing: PulseSpacing.sm + 2) {
                            Image(systemName: result.verified ? "checkmark.seal.fill" : "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(result.verified ? PulseColors.success : PulseColors.danger)
                            VStack(alignment: .leading, spacing: PulseSpacing.xxs) {
                                Text(result.verified ? "Pulse Verified!" : "Not Yet Complete")
                                    .font(PulseTypography.labelLargeEmphasized)
                                    .foregroundColor(result.verified ? PulseColors.success : PulseColors.danger)
                                Text(result.feedback)
                                    .font(PulseTypography.bodySmall)
                                    .foregroundColor(PulseColors.textSecondary)
                            }
                        }
                        .padding(PulseSpacing.lg)
                        .background((result.verified ? PulseColors.success : PulseColors.danger).opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
                    }

                    if verificationResult?.verified != true {
                        Button {
                            Task { await submitProof() }
                        } label: {
                            HStack {
                                if isVerifying {
                                    ProgressView()
                                        .tint(PulseColors.onPrimary)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                }
                                Text(isVerifying ? "AI is verifying..." : "Submit & Verify")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(M3FilledButton())
                        .disabled((proofText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoData == nil) || isVerifying)
                    }
                }
                .padding(PulseSpacing.screenEdge)
                .padding(.bottom, PulseSpacing.section)
            }
            .pulseScreen()
            .navigationTitle("Submit Proof")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Restore any prior proof so reopening the sheet shows what was
                // already submitted (text, photo) and the AI's reason on rejection.
                if proofText.isEmpty { proofText = step.proofNotes ?? "" }
                if photoData == nil, let saved = loadSavedProofPhoto() { photoData = saved }
                if step.verificationStatus == "rejected",
                   verificationResult == nil,
                   let response = step.verificationAIResponse, !response.isEmpty {
                    verificationResult = (false, response)
                }
            }
            // toolbar follows system color scheme
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(PulseColors.textSecondary)
                }
            }
        }
    }

    private func submitProof() async {
        isVerifying = true
        let trimmedProof = proofText.trimmingCharacters(in: .whitespacesAndNewlines)

        // AI proof verification runs for ALL tiers — AI is free for everyone.
        let result: (verified: Bool, feedback: String)
        if let photoData = photoData {
            result = await StepVerificationService.shared.verifyWithPhoto(step: step, photoData: photoData, proofText: trimmedProof, context: viewContext)
        } else {
            result = await StepVerificationService.shared.verifyStepCompletion(step: step, proofText: trimmedProof, context: viewContext)
        }
        verificationResult = result
        if result.verified {
            markStepComplete(feedback: result.feedback)
        } else {
            step.verificationStatus = "rejected"
            step.verificationAIResponse = result.feedback
            step.proofNotes = trimmedProof
            if let filename = persistProofPhoto() { step.proofSubmission = filename }
            try? viewContext.save()
        }

        isVerifying = false

        if verificationResult?.verified == true {
            PulseHaptics.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        }
    }

    private func markStepComplete(feedback: String) {
        step.isCompleted = true
        step.completedDate = Date()
        step.verificationStatus = "verified"
        step.verificationAIResponse = feedback
        step.proofNotes = proofText
        if let filename = persistProofPhoto() { step.proofSubmission = filename }

        let profile = UserProfile.fetchOrCreate(in: viewContext)

        let totalSteps = Double(goal.totalSteps)
        let completedSteps = Double(goal.completedSteps)
        if totalSteps > 0 { goal.currentProgress = Float((completedSteps / totalSteps) * 100) }

        // If that was the last step, finish the goal and stop its reminders so
        // the daily "How did your pulse go? log it" check-in can't keep firing.
        let goalID = goal.id?.uuidString ?? ""
        let justCompleted = goal.markCompletedIfAllStepsDone()

        try? viewContext.save()

        if justCompleted {
            AdaptiveNotificationScheduler.handleGoalCompletion(goalID: goalID)
        }

        // Big celebration (also bumps XP + level)
        let nextStep = goal.allSteps.first(where: { !$0.isCompleted && $0.objectID != step.objectID })
        appState.celebratePulseCompletion(
            pulseNumber: Int(step.stepNumber),
            nextPulseTitle: nextStep?.titleValue,
            profile: profile,
            xpReward: Int(step.xpReward),
            in: viewContext
        )
    }
}
