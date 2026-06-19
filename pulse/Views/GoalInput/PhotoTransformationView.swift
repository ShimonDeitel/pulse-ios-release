import SwiftUI
import PhotosUI
import CoreData

struct PhotoTransformationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState
    @StateObject private var service = PhotoTransformationService.shared

    @State private var currentPhotoItem: PhotosPickerItem?
    @State private var goalPhotoItem: PhotosPickerItem?
    @State private var currentImage: UIImage?
    @State private var goalImage: UIImage?
    @State private var didCreateGoal = false
    // The user dismissed this screen. On a slow connection an AI result can land
    // AFTER Cancel — this flag (plus clearing service.analysisResult on dismiss)
    // stops a late result from silently auto-creating a goal behind their back.
    @State private var dismissed = false
    @State private var showingCurrentCamera = false
    @State private var showingGoalCamera = false

    // New inputs per spec
    @State private var trainingStyle: TrainingStyle = .gym
    @State private var weightUnit: WeightUnit = .lb
    // Empty by default so the "e.g. 165" placeholder shows as a gray hint that
    // clears the moment the user types — we never pre-fill a real number.
    @State private var weightText: String = ""
    @State private var targetWeeks: Double = 12

    private var weightValue: Double {
        Double(weightText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSubmit: Bool {
        currentImage != nil && goalImage != nil && weightValue > 0 && targetWeeks >= 4
    }

    /// Names exactly what is still missing so the disabled button is never a mystery.
    private var missingRequirement: String? {
        if currentImage == nil && goalImage == nil { return "Add a current photo and a goal photo to continue." }
        if currentImage == nil { return "Add a photo of how you look now." }
        if goalImage == nil { return "Add a photo of the goal physique you want." }
        if weightValue <= 0 { return "Enter your current weight (a number greater than 0)." }
        if targetWeeks < 4 { return "Pick at least 4 weeks." }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: PulseSpacing.xxl) {
                    header
                    photoRow
                    trainingStylePicker
                    weightField
                    weeksField
                    tipsCard
                    if let err = service.error {
                        errorBanner(err)
                    }
                    if service.error == nil, !service.isAnalyzing, let missing = missingRequirement {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(PulseColors.textTertiary)
                            Text(missing)
                                .font(PulseTypography.bodySmall)
                                .foregroundColor(PulseColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PulseSpacing.screenEdge)
                    }
                    actionButton
                }
                .padding(.bottom, PulseSpacing.section)
            }
            .pulseScreen()
            .navigationTitle("Transform")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // Mark dismissed and drop any in-flight/late result so a
                        // result that lands after this tap can't auto-create a goal.
                        dismissed = true
                        service.analysisResult = nil
                        dismiss()
                    }
                    .foregroundColor(PulseColors.primary)
                }
            }
            .onChange(of: currentPhotoItem) { loadImage(from: currentPhotoItem) { currentImage = $0; persistDraftPhotos() } }
            .onChange(of: goalPhotoItem)    { loadImage(from: goalPhotoItem)    { goalImage = $0; persistDraftPhotos() } }
            // Persist the scalar inputs the moment any of them changes, so a draft
            // never loses the weeks / weight / training style.
            .onChange(of: trainingStyle) { persistDraftFields() }
            .onChange(of: weightText)    { persistDraftFields() }
            .onChange(of: weightUnit)    { persistDraftFields() }
            .onChange(of: targetWeeks)   { persistDraftFields() }
            .sheet(isPresented: $showingCurrentCamera) { CameraImagePicker(image: $currentImage) }
            .sheet(isPresented: $showingGoalCamera)    { CameraImagePicker(image: $goalImage) }
            // Resume a saved Transformation draft: restore its before/after photos
            // AND its scalar inputs (target weeks, current weight + unit, style).
            .onAppear {
                if currentImage == nil, goalImage == nil {
                    let saved = DraftService.shared.draftPhotos(.transformation)
                    if let d = saved.current { currentImage = UIImage(data: d) }
                    if let d = saved.goal    { goalImage    = UIImage(data: d) }
                }
                let f = DraftService.shared.draftFields(.transformation)
                if let s = f["trainingStyle"], let ts = TrainingStyle(rawValue: s) { trainingStyle = ts }
                if let w = f["weight"] { weightText = w }
                if let u = f["weightUnit"], let wu = WeightUnit(rawValue: u) { weightUnit = wu }
                if let wk = f["weeks"], let n = Double(wk), n >= 4 { targetWeeks = n }
            }
            // Leaving without finishing keeps the photos + inputs in the draft;
            // creating the goal clears them (handled in createGoalFromPlan).
            // Also mark dismissed and drop any late result so a slow AI response
            // arriving after we've gone can't auto-create a goal (covers swipe-to-
            // dismiss, not just the Cancel button).
            .onDisappear {
                if !didCreateGoal {
                    dismissed = true
                    service.analysisResult = nil
                    persistDraftPhotos()
                    persistDraftFields()
                }
            }
            // When the AI returns a plan, create the goal automatically and dismiss.
            .onChange(of: service.analysisResult != nil) {
                if let plan = service.analysisResult {
                    createGoalFromPlan(plan)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: PulseSpacing.sm + 2) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(PulseColors.primary)
            Text("Transformation")
                .font(PulseTypography.headlineLarge)
                .foregroundColor(PulseColors.textPrimary)
                .headlineTracking()
            Text("A photo of you now, and your goal. We'll build the plan.")
                .font(PulseTypography.bodyMedium)
                .foregroundColor(PulseColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PulseSpacing.screenEdge)
        }
        .padding(.top, PulseSpacing.md)
    }

    private var photoRow: some View {
        HStack(spacing: PulseSpacing.lg) {
            PhotoPickerCard(title: "Current Me", subtitle: "How you look now",
                            image: currentImage, icon: "person.fill", color: PulseColors.signal) {
                VStack(spacing: 6) {
                    Button { showingCurrentCamera = true } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PulseColors.signal)
                    }
                    PhotosPicker(selection: $currentPhotoItem, matching: .images) {
                        Label("Library", systemImage: "photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PulseColors.signal)
                    }
                }
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(PulseColors.textTertiary)
            PhotoPickerCard(title: "Goal Me", subtitle: "How you want to look",
                            image: goalImage, icon: "star.fill", color: PulseColors.signal) {
                VStack(spacing: 6) {
                    Button { showingGoalCamera = true } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PulseColors.signal)
                    }
                    PhotosPicker(selection: $goalPhotoItem, matching: .images) {
                        Label("Library", systemImage: "photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PulseColors.signal)
                    }
                }
            }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var trainingStylePicker: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("TRAINING STYLE")
                .font(PulseTypography.eyebrow)
                .foregroundColor(PulseColors.textTertiary)
                .eyebrowTracking()
            HStack(spacing: 10) {
                ForEach(TrainingStyle.allCases) { style in
                    Button {
                        trainingStyle = style
                        PulseHaptics.light()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: style.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(trainingStyle == style ? .white : PulseColors.signal)
                            Text(style.shortName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(trainingStyle == style ? .white : PulseColors.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(trainingStyle == style ? PulseColors.signal : PulseColors.surfaceContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(trainingStyle == style ? Color.clear : PulseColors.hair, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text("YOUR CURRENT WEIGHT")
                .font(PulseTypography.eyebrow)
                .foregroundColor(PulseColors.textTertiary)
                .eyebrowTracking()
            HStack(spacing: 10) {
                TextField("e.g. 165", text: $weightText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.ink)
                    .padding(14)
                    .background(PulseColors.surfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Picker("", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { u in
                        Text(u.label).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var weeksField: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            HStack {
                Text("HOW MANY WEEKS")
                    .font(PulseTypography.eyebrow)
                    .foregroundColor(PulseColors.textTertiary)
                    .eyebrowTracking()
                Spacer()
                Text("\(Int(targetWeeks)) \(Int(targetWeeks) == 1 ? "week" : "weeks")")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(PulseColors.signal)
            }
            Slider(value: $targetWeeks, in: 4...52, step: 1)
                .tint(PulseColors.signal)
            Text("Pick anything from 4 weeks to a year. Real change takes at least a month — the AI builds the most realistic plan for the time you give it.")
                .font(.system(size: 11))
                .foregroundColor(PulseColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm + 2) {
            Text("TIPS FOR THE BEST PLAN")
                .font(PulseTypography.eyebrow)
                .foregroundColor(PulseColors.textTertiary)
                .eyebrowTracking()
            TipRow(icon: "camera.fill", text: "Well-lit, full-body photos work best")
            TipRow(icon: "tshirt.fill",  text: "Wear fitted clothing — easier to assess composition")
            TipRow(icon: "person.fill.viewfinder", text: "Same angle for both photos if possible")
            TipRow(icon: "lock.fill",    text: "Photos are processed in memory and never stored on our servers")
        }
        .padding(PulseSpacing.lg)
        .background(PulseColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(PulseColors.signal)
                Text("Couldn't build your plan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(PulseColors.ink)
                Spacer()
                Button {
                    service.error = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(PulseColors.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(message)
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                service.error = nil
                startGeneration()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Try again")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(PulseColors.signal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || service.isAnalyzing)
        }
        .padding(PulseSpacing.lg)
        .background(PulseColors.signal.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                .stroke(PulseColors.signal.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    private var actionButton: some View {
        Button {
            startGeneration()
        } label: {
            HStack(spacing: 8) {
                if service.isAnalyzing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                    Text("Building your plan…")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Create Plan")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSubmit ? PulseColors.signal : PulseColors.muted.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSubmit || service.isAnalyzing)
        .padding(.horizontal, PulseSpacing.screenEdge)
    }

    // MARK: - Actions

    private func startGeneration() {
        guard let current = currentImage, let goal = goalImage else {
            service.error = missingRequirement ?? "Add both photos to build your plan."
            PulseHaptics.error()
            return
        }
        PulseHaptics.medium()
        Task {
            await service.generatePlan(
                currentPhoto: current,
                goalPhoto: goal,
                trainingStyle: trainingStyle,
                weight: weightValue,
                weightUnit: weightUnit,
                targetWeeks: Int(targetWeeks)
            )
            // AI-ONLY: if the vision AI failed, we create NOTHING. The error
            // banner (incl. "Usage limit hit") is already shown via
            // service.error. Pulse never fabricates a fake plan.
        }
    }

    /// Turn the AI plan into a real Goal + DailyTasks for each workout day,
    /// then close the sheet. Detail page renders the rest.
    private func createGoalFromPlan(_ plan: TransformationPlan) {
        // Guard against a late AI result: if the user already dismissed (Cancel /
        // swipe) or we've already created the goal, do NOT silently auto-create a
        // goal behind their back.
        guard !dismissed, !didCreateGoal else { return }
        let goal = Goal(context: viewContext)
        goal.id = UUID()
        goal.title = "Transformation"
        goal.goalDescription = plan.assessment
        goal.category = "transformation"   // distinct category for routing
        goal.status = GoalStatus.active.rawValue
        goal.deadline = Calendar.current.date(byAdding: .weekOfYear, value: plan.estimatedWeeks, to: Date())
        goal.currentProgress = 0
        goal.aiProbabilityScore = 75
        goal.availableTimePerDay = 60
        goal.skillLevel = SkillLevel.beginner.rawValue
        goal.motivationLevel = 8
        goal.urgencyLevel = UrgencyLevel.high.rawValue
        goal.createdAt = Date()

        // Store the entire plan as JSON in aiRoadmapJSON for the detail screen
        if let data = try? JSONEncoder().encode(plan),
           let json = String(data: data, encoding: .utf8) {
            goal.aiRoadmapJSON = json
        }

        // Persist the before/after photos locally for instant render…
        if let current = service.currentPhotoData,
           let goalImg = service.goalPhotoData {
            UserDefaults.standard.set(current, forKey: "transformation_current_\(goal.id?.uuidString ?? "")")
            UserDefaults.standard.set(goalImg, forKey: "transformation_goal_\(goal.id?.uuidString ?? "")")

            // …and upload them to the user's private iCloud (CloudKit) so they
            // survive reinstall; access is limited to the user's own iCloud.
            let goalIDString = goal.id?.uuidString ?? UUID().uuidString
            Task.detached(priority: .utility) {
                let currentURL = await FirestoreSyncService.shared.uploadTransformationPhoto(
                    data: current, kind: "current", goalId: goalIDString)
                let goalURL = await FirestoreSyncService.shared.uploadTransformationPhoto(
                    data: goalImg, kind: "goal", goalId: goalIDString)
                if let cu = currentURL { UserDefaults.standard.set(cu, forKey: "transformation_current_url_\(goalIDString)") }
                if let gu = goalURL    { UserDefaults.standard.set(gu, forKey: "transformation_goal_url_\(goalIDString)") }
            }
        }

        let profile = UserProfile.fetchOrCreate(in: viewContext)
        goal.userProfile = profile

        // One DailyTask per workout day so existing pulse-completion + widget
        // machinery works for transformation goals too.
        for workout in plan.workouts {
            let task = DailyTask(context: viewContext)
            task.id = UUID()
            task.title = workout.isRestDay ? "Rest day — \(workout.title)" : workout.title
            task.taskDescription = workout.focus
            task.howToDescription = workout.exercises.enumerated().map { idx, ex in
                let notes = ex.notes.map { " — \($0)" } ?? ""
                return "\(idx + 1). \(ex.name) — \(ex.sets) × \(ex.reps), rest \(ex.restSeconds)s\(notes)"
            }.joined(separator: "\n")
            task.proofType = "text"
            task.proofDescription = workout.isRestDay
                ? "Note any recovery work or how you felt."
                : "Tell us how the workout went — weights used, perceived effort, anything notable."
            task.stepNumber = Int16(clamping: workout.dayOffset + 1)
            task.sortOrder = Int16(clamping: workout.dayOffset)
            task.estimatedMinutes = Int16(clamping: workout.estimatedMinutes)
            task.scheduledDate = Calendar.current.date(byAdding: .day, value: workout.dayOffset, to: Date())
            task.xpReward = 15
            task.verificationStatus = "pending"
            task.goal = goal
        }

        try? viewContext.save()
        WidgetDataService.shared.updateWidgets(context: viewContext)
        AdaptiveNotificationScheduler.shared.refreshFromSettings()
        PulseHaptics.success()

        // Reset service so reopening starts fresh next time
        service.analysisResult = nil
        service.currentPhotoData = nil
        service.goalPhotoData = nil

        // The goal is now real — drop the saved draft photos + scalar inputs so a
        // future Transformation starts blank (and onDisappear doesn't re-save them).
        didCreateGoal = true
        DraftService.shared.clearDraftPhotos(.transformation)
        DraftService.shared.clearDraftFields(.transformation)

        DispatchQueue.main.async { dismiss() }
    }

    /// Persist the picked before/after photos into the Transformation draft so
    /// they survive backing out and are restored on resume. Downscaled to keep
    /// the on-disk cache small.
    private func persistDraftPhotos() {
        DraftService.shared.saveDraftPhotos(
            .transformation,
            current: currentImage.flatMap(jpegForDraft),
            goal: goalImage.flatMap(jpegForDraft)
        )
    }

    /// Persist the scalar Transformation inputs (target weeks, current weight +
    /// unit, training style) into the draft so they survive backing out and are
    /// restored on resume — not just the photos.
    private func persistDraftFields() {
        guard !didCreateGoal else { return }
        DraftService.shared.saveDraftFields(.transformation, [
            "trainingStyle": trainingStyle.rawValue,
            "weight": weightText,
            "weightUnit": weightUnit.rawValue,
            "weeks": String(Int(targetWeeks))
        ])
    }

    private func jpegForDraft(_ image: UIImage) -> Data? {
        guard let full = image.jpegData(compressionQuality: 0.9) else { return nil }
        return DeepSeekClient.downscaledJPEG(full, maxDimension: 1024, quality: 0.6) ?? full
    }

    private func loadImage(from item: PhotosPickerItem?, completion: @escaping (UIImage?) -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { completion(image) }
            }
        }
    }
}

// MARK: - Photo picker card

struct PhotoPickerCard<Picker: View>: View {
    let title: String
    let subtitle: String
    let image: UIImage?
    let icon: String
    let color: Color
    @ViewBuilder let picker: Picker

    var body: some View {
        VStack(spacing: PulseSpacing.sm + 2) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 130, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: PulseSpacing.cardRadius, style: .continuous)
                    .fill(PulseColors.surfaceContainer)
                    .frame(width: 130, height: 170)
                    .overlay(
                        VStack(spacing: PulseSpacing.sm) {
                            Image(systemName: icon)
                                .font(.system(size: 28, weight: .ultraLight))
                                .foregroundColor(color.opacity(0.5))
                            Text(subtitle)
                                .font(PulseTypography.labelSmall)
                                .foregroundColor(PulseColors.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                    )
            }
            Text(title)
                .font(PulseTypography.labelLargeEmphasized)
                .foregroundColor(PulseColors.textPrimary)
            picker
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: PulseSpacing.sm + 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(PulseColors.primary)
                .frame(width: 20)
            Text(text)
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Camera Image Picker

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
