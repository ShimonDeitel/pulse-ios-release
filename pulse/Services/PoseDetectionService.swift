import Foundation
import AVFoundation
import Vision
import UIKit

/// Real-time human-pose detection using Apple's Vision framework.
/// Publishes whether a person is currently in frame, estimated rep count
/// (vertical motion of the shoulders), and a stream of form hints.
@MainActor
@Observable
final class PoseDetectionService: NSObject {

    // MARK: - Public state

    /// True if a person is currently detected in the frame.
    var personInFrame: Bool = false

    /// Most recent shoulder-y position (avg of left+right). Used for rep counting.
    var smoothedShoulderY: CGFloat = 0

    /// Number of full reps detected since calibration.
    var repCount: Int = 0

    /// Short form-coaching hints surfaced from joint angles.
    /// Empty when posture looks OK.
    var formHints: [String] = []

    /// Confidence the user has actually started moving (0–1).
    /// Triggers the workout countdown once it crosses 0.6.
    var motionConfidence: Double = 0

    /// Latest detected joint positions in NORMALIZED Vision coordinates
    /// (x and y in 0…1; y=0 is BOTTOM). The skeleton overlay reads this.
    /// SMOOTHED across frames via exponential moving average so the skeleton
    /// doesn't jitter on noisy detections — looks anchored to the body.
    var jointPositions: [PoseJoint: CGPoint] = [:]

    /// True only when we have a confident, full-body detection. Used by
    /// the UI to show "stand back so we can see your full body" guidance.
    var hasFullBodyView: Bool = false

    /// Form quality right now — drives the overlay color.
    /// True (green) means the rep state machine is happy with what it
    /// sees. False (red) means current movement won't count: low joint
    /// confidence, hips sagging, etc.
    var formIsGood: Bool = false

    /// True when the user has denied/restricted camera access. The Live
    /// workout view watches this to show a Settings-link overlay instead
    /// of a permanent black preview.
    var cameraAuthDenied: Bool = false

    /// Hysteresis state — keep the skeleton color stable across frames.
    /// Stored on the class (not the extension where `apply` lives,
    /// because Swift forbids stored properties in extensions).
    fileprivate var goodFrameStreak: Int = 0
    fileprivate var badFrameStreak: Int = 0

    // MARK: - Camera plumbing

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "pulse.posedetection.video")

    private let detector = HumanPoseDetector()

    // Active exercise — informs rep counting strategy + form hints
    var activeExercise: String = ""

    // Capture stays in a FIXED portrait orientation. The Live workout screen
    // rotates the whole SwiftUI view (preview + skeleton + HUD) together via a
    // rotationEffect, so the camera connection must NOT also rotate — otherwise
    // the feed would double-rotate and the skeleton would misalign. Vision reads
    // the portrait buffer as `.up`; mirroring is handled by isVideoMirrored.

    // MARK: - Lifecycle

    /// Start the front-facing camera + Vision pipeline.
    func start() async {
        await requestCameraAccessIfNeeded()
        configureSessionIfNeeded()
        if !captureSession.isRunning {
            Task.detached { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    func stop() {
        if captureSession.isRunning { captureSession.stopRunning() }
        personInFrame = false
        motionConfidence = 0
        repCount = 0
        smoothedShoulderY = 0
        formHints = []
    }

    /// Resets motion + rep state when an exercise begins.
    func resetForExercise(_ name: String) {
        activeExercise = name
        repCount = 0
        smoothedShoulderY = 0
        motionConfidence = 0
        formHints = []
        Task { await detector.reset() }
    }

    // MARK: - Setup

    private func requestCameraAccessIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { cameraAuthDenied = !granted }
        case .denied, .restricted:
            await MainActor.run { cameraAuthDenied = true }
        case .authorized:
            await MainActor.run { cameraAuthDenied = false }
        @unknown default:
            await MainActor.run { cameraAuthDenied = false }
        }
    }

    private var configured = false
    private func configureSessionIfNeeded() {
        guard !configured else { return }
        configured = true
        registerSessionObservers()

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        // FRONT (selfie) camera — the user wants to see themselves in the
        // frame as they exercise, so they can verify their form against
        // the green/red skeleton overlay.
        let pickedDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let device = pickedDevice,
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // Mirror — selfie camera should show the user as if in a mirror.
            connection.isVideoMirrored = true
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Interruption / media-services-reset recovery
    //
    // An incoming phone call (or any media-services reset) can interrupt the
    // capture session or invalidate it entirely. Without handling these, the
    // camera path can wedge or crash. We observe the relevant notifications and
    // safely restart the session off the main thread.

    private func registerSessionObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleSessionRuntimeError(_:)),
                       name: .AVCaptureSessionRuntimeError, object: captureSession)
        nc.addObserver(self, selector: #selector(handleInterruptionEnded(_:)),
                       name: .AVCaptureSessionInterruptionEnded, object: captureSession)
        nc.addObserver(self, selector: #selector(handleMediaServicesReset(_:)),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @objc nonisolated private func handleSessionRuntimeError(_ note: Notification) {
        restartSessionSoon()
    }

    @objc nonisolated private func handleInterruptionEnded(_ note: Notification) {
        restartSessionSoon()
    }

    @objc nonisolated private func handleMediaServicesReset(_ note: Notification) {
        restartSessionSoon()
    }

    /// Restart the capture session on a background queue if it isn't running.
    /// Tolerant of any state — never throws, never blocks the main thread.
    nonisolated private func restartSessionSoon() {
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.4) {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Vision frame processing

extension PoseDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await detector.detect(in: pixelBuffer, exercise: activeExercise)
            apply(result)
        }
    }

    private func apply(_ r: PoseDetectionResult) {
        personInFrame = r.personDetected
        if r.personDetected {
            smoothedShoulderY = r.smoothedShoulderY
            motionConfidence = r.motionConfidence
            // The push-up detector (detectPushUpRep) already enforces the
            // form gate: plank body + symmetric arms + torso motion. If
            // it says "rep!" the rep IS real, count it. Don't double-gate
            // on formIsGood (skeleton color) — that was rejecting valid
            // reps when Vision briefly dropped a joint at the bottom of
            // the descent and the skeleton flickered red.
            //
            // Skeleton color is now purely a VISUAL signal for the user
            // ("tracking confident" vs "lost some joints"), not part of
            // the rep-count decision.
            if r.didCompleteRep {
                repCount += 1
            }
            formHints = r.hints

            // ── Temporal smoothing on joint positions ──────────────
            // Vision's per-frame jitter (5-15 px wobble even when the
            // user is still) makes the skeleton look like it's "glitching
            // off the body." Apply an exponential moving average so each
            // joint glides to its new position over ~4 frames. New joints
            // (not in the previous map) snap directly to their detection.
            let alpha: CGFloat = 0.35  // higher = snappier, lower = smoother
            var smoothed: [PoseJoint: CGPoint] = [:]
            for (joint, target) in r.joints {
                if let prev = jointPositions[joint] {
                    smoothed[joint] = CGPoint(
                        x: prev.x + (target.x - prev.x) * alpha,
                        y: prev.y + (target.y - prev.y) * alpha
                    )
                } else {
                    smoothed[joint] = target
                }
            }
            jointPositions = smoothed

            // "Full body" = both shoulders + both hips + at least one
            // leg-pair joint set. Anything less, we can't draw a credible
            // figure and we ask the user to step back.
            let hasShoulders = smoothed[.leftShoulder] != nil && smoothed[.rightShoulder] != nil
            let hasHips = smoothed[.leftHip] != nil && smoothed[.rightHip] != nil
            let hasLegs = (smoothed[.leftKnee] != nil || smoothed[.rightKnee] != nil) ||
                          (smoothed[.leftAnkle] != nil || smoothed[.rightAnkle] != nil)
            hasFullBodyView = hasShoulders && hasHips && hasLegs

            // ── Hysteresis ─────────────────────────────────────────
            // FAST to turn green (2 good frames), VERY SLOW to turn
            // red (24 bad frames ≈ 1 full second at 24fps). User said
            // the green light only flashed for a fraction of a second
            // — that was the old 8-frame red threshold being too quick
            // to revert. Now green sticks through normal joint-confidence
            // jitter and only flips back if the user is genuinely out
            // of position for ~1 second.
            if r.formIsGood {
                goodFrameStreak += 1
                badFrameStreak = 0
                if goodFrameStreak >= 2 { formIsGood = true }
            } else {
                badFrameStreak += 1
                goodFrameStreak = 0
                if badFrameStreak >= 24 { formIsGood = false }
            }
        } else {
            motionConfidence = max(0, motionConfidence - 0.15)
            jointPositions = [:]
            hasFullBodyView = false
            badFrameStreak += 1
            goodFrameStreak = 0
            if badFrameStreak >= 24 { formIsGood = false }
        }
    }
}

// MARK: - Detection logic (isolated actor so we can keep state across frames)

/// Skeleton points we render in the overlay. Most come directly from
/// Vision's body-pose detector; the ones marked DERIVED are computed
/// midpoints so the skeleton has more detail along each limb (user
/// requested centimeter-accurate joints on biceps, forearms, thighs,
/// shins — Vision doesn't expose these directly, so we compute them).
enum PoseJoint: String, CaseIterable, Sendable {
    case head            // DERIVED: center of detected head (mid-nose to neck)
    case nose, neck
    case leftShoulder, rightShoulder
    case leftBicep, rightBicep        // DERIVED: midpoint shoulder ↔ elbow
    case leftElbow, rightElbow
    case leftForearm, rightForearm    // DERIVED: midpoint elbow ↔ wrist
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftThigh, rightThigh        // DERIVED: midpoint hip ↔ knee
    case leftKnee, rightKnee
    case leftShin, rightShin          // DERIVED: midpoint knee ↔ ankle
    case leftAnkle, rightAnkle

    /// True for midpoints we compute. Used by the form-quality check so
    /// derived points don't inflate the "joints detected" count.
    var isDerived: Bool {
        switch self {
        case .head,
             .leftBicep, .rightBicep,
             .leftForearm, .rightForearm,
             .leftThigh, .rightThigh,
             .leftShin, .rightShin:
            return true
        default:
            return false
        }
    }

    /// Radius of the joint dot in the skeleton overlay.
    /// Major endpoint joints (head, hands, knees, ankles) are bigger so
    /// the user can clearly see them. Mid-limb derived joints (biceps,
    /// forearms, thighs, shins) are smaller — they're for visual continuity.
    var dotRadius: CGFloat {
        switch self {
        case .head, .leftWrist, .rightWrist,
             .leftKnee, .rightKnee,
             .leftAnkle, .rightAnkle:
            return 7      // BIG — the joints the user explicitly listed
        case .nose, .neck,
             .leftShoulder, .rightShoulder,
             .leftElbow, .rightElbow,
             .leftHip, .rightHip:
            return 5      // medium — primary skeleton anchors
        default:
            return 3      // small — derived midpoints
        }
    }
}

struct PoseDetectionResult: Sendable {
    let personDetected: Bool
    let smoothedShoulderY: CGFloat
    let motionConfidence: Double
    let didCompleteRep: Bool
    let hints: [String]
    let joints: [PoseJoint: CGPoint]
    let formIsGood: Bool
}

actor HumanPoseDetector {
    private let request = VNDetectHumanBodyPoseRequest()

    // Motion confidence — pixels of movement over last ~30 frames.
    // Used only to trigger the "user has started moving" countdown,
    // NOT for rep counting.
    private var lastShoulder: CGFloat = 0
    private var movement: Double = 0

    // ── Joint-angle-based rep state machine ─────────────────────────────
    // For push-ups: tracks elbow angle. State flips between .extended
    // (>= 150°) and .flexed (<= 105°). Each full extended→flexed→extended
    // cycle counts as exactly one rep. Random head bobbing, swaying,
    // shifting weight — none of it changes the elbow angle, so none of it
    // can fake a rep.
    //
    // For squats: tracks knee angle the same way (standing >=160°, deep
    // <=110°).
    //
    // For pull-ups: tracks shoulder-vs-wrist Y delta (hanging vs pulled-up).
    enum AngleState { case extended, flexed }
    private var angleState: AngleState = .extended
    private var lastRepAt: TimeInterval = 0

    // Push-up specific: record the shoulder Y position when we ENTER the
    // flexed state, so we can verify the body actually moved vertically
    // during the rep. A real push-up moves the torso ~10-20% of frame
    // height. Random arm waving doesn't move the torso at all.
    private var shoulderYAtFlexStart: CGFloat = 0

    // Spatial lock on the tracked person. Vision gives no stable identity across
    // frames, so we remember the selected body's centroid and each frame stay on
    // whoever is closest to it — keeping the skeleton on the SAME foreground person
    // even when their joints flicker mid-rep, instead of jumping to a fully-visible
    // bystander. Reset between exercises / sessions.
    private var lockedCentroid: CGPoint?

    func reset() {
        lastShoulder = 0
        movement = 0
        angleState = .extended
        lastRepAt = 0
        shoulderYAtFlexStart = 0
        legRaiseEnvelope = []
        smoothedAngle = 180
        torsoHistory = []
        torsoState = .extended
        lockedCentroid = nil
    }

    /// EMA-smoothed joint angle. Vision's per-frame angle estimate jitters by
    /// several degrees even when you hold still, which made the rep state machine
    /// fire phantom reps and miss real ones. Smoothing over ~3 frames before the
    /// threshold checks makes counting dramatically more reliable. Shared across
    /// the angle-based detectors (only one exercise is active at a time; reset()
    /// re-arms it).
    private var smoothedAngle: Double = 180
    private func smoothAngle(_ a: Double) -> Double {
        smoothedAngle = smoothedAngle * 0.6 + a * 0.4
        return smoothedAngle
    }

    /// Frame-area spanned by an observation's confident joints — a proxy for how
    /// CLOSE that person is (closer to the camera = larger span). Used to pick the
    /// single foreground user when multiple people are in frame.
    private static func bodySpan(_ obs: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? obs.recognizedPoints(.all) else { return 0 }
        let conf = pts.values.filter { $0.confidence > 0.1 }
        guard conf.count >= 2 else { return 0 }
        let xs = conf.map { $0.location.x }
        let ys = conf.map { $0.location.y }
        let w = (xs.max() ?? 0) - (xs.min() ?? 0)
        let h = (ys.max() ?? 0) - (ys.min() ?? 0)
        return w * h
    }

    /// Centroid of an observation's confident joints, in Vision's normalized
    /// frame coords (0…1). Used to associate the same person across frames.
    private static func bodyCentroid(_ obs: VNHumanBodyPoseObservation) -> CGPoint? {
        guard let pts = try? obs.recognizedPoints(.all) else { return nil }
        let conf = pts.values.filter { $0.confidence > 0.1 }
        guard !conf.isEmpty else { return nil }
        let n = CGFloat(conf.count)
        let cx = conf.reduce(CGFloat(0)) { $0 + $1.location.x } / n
        let cy = conf.reduce(CGFloat(0)) { $0 + $1.location.y } / n
        return CGPoint(x: cx, y: cy)
    }

    /// Pick which body to track. Once locked onto someone, STAY on the body whose
    /// centroid is nearest the lock (same person) so a momentary drop in their
    /// confident-joint span mid-rep can't hand the skeleton to a fully-visible
    /// bystander. Only re-acquire — the person filling the MOST of the frame
    /// (largest joint span = closest to camera) — when nobody is near the lock
    /// (the tracked user has left the frame).
    private func selectTrackedBody(_ bodies: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        guard !bodies.isEmpty else { return nil }
        if let locked = lockedCentroid {
            var best: (obs: VNHumanBodyPoseObservation, dist: CGFloat)?
            for obs in bodies {
                guard let c = Self.bodyCentroid(obs) else { continue }
                let d = hypot(c.x - locked.x, c.y - locked.y)
                if best == nil || d < best!.dist { best = (obs, d) }
            }
            // Same person if their centroid hasn't jumped more than ~22% of the
            // frame since last frame (generous at 30fps, far tighter than the gap
            // to a background bystander).
            if let best, best.dist < 0.22 { return best.obs }
        }
        return bodies.max(by: { Self.bodySpan($0) < Self.bodySpan($1) })
    }

    func detect(in pixelBuffer: CVPixelBuffer, exercise: String) async -> PoseDetectionResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return PoseDetectionResult(personDetected: false, smoothedShoulderY: 0,
                                       motionConfidence: 0, didCompleteRep: false,
                                       hints: [], joints: [:], formIsGood: false)
        }
        // Track ONLY the person CLOSEST to the camera: the observation whose
        // confident joints span the largest area of the frame (closer = bigger).
        // This locks the skeleton onto the foreground user and stops it jumping
        // to other people in the background.
        let bodies = (request.results as? [VNHumanBodyPoseObservation]) ?? []
        guard let observation = selectTrackedBody(bodies),
              let recognized = try? observation.recognizedPoints(.all) else {
            return PoseDetectionResult(personDetected: false, smoothedShoulderY: 0,
                                       motionConfidence: max(0, movement - 0.05),
                                       didCompleteRep: false, hints: [],
                                       joints: [:], formIsGood: false)
        }
        // Update the spatial lock to the person we just chose, so next frame stays
        // on them (see selectTrackedBody).
        if let c = Self.bodyCentroid(observation) { lockedCentroid = c }

        // Vision: y=0 bottom, y=1 top.
        let ls = recognized[.leftShoulder]
        let rs = recognized[.rightShoulder]
        let lh = recognized[.leftHip]
        let rh = recognized[.rightHip]
        let le = recognized[.leftElbow]
        let re = recognized[.rightElbow]
        let lw = recognized[.leftWrist]
        let rw = recognized[.rightWrist]
        let lk = recognized[.leftKnee]
        let rk = recognized[.rightKnee]
        let la = recognized[.leftAnkle]
        let ra = recognized[.rightAnkle]

        // Anchor on the shoulders, but only ONE needs to be visible. The old
        // gate required BOTH shoulders > 0.25 and discarded the entire frame
        // otherwise — which is exactly the bottom of a push-up / sit-up / leg
        // raise (a shoulder dips behind the torso right as the rep completes),
        // so real reps were being thrown away. Accept a single confident
        // shoulder at a lower floor and mirror it so downstream detectors
        // still have both anchors.
        let shoulderFloor: Float = 0.12
        let lsOK = (ls?.confidence ?? 0) > shoulderFloor
        let rsOK = (rs?.confidence ?? 0) > shoulderFloor
        guard lsOK || rsOK else {
            return PoseDetectionResult(personDetected: false, smoothedShoulderY: 0,
                                       motionConfidence: max(0, movement - 0.05),
                                       didCompleteRep: false, hints: [],
                                       joints: [:], formIsGood: false)
        }
        let leftS: VNRecognizedPoint = lsOK ? ls! : rs!
        let rightS: VNRecognizedPoint = rsOK ? rs! : ls!

        let shoulderY = (leftS.location.y + rightS.location.y) / 2
        let movementDelta = abs(shoulderY - lastShoulder)
        lastShoulder = shoulderY
        // Exponential smoothing for motion confidence (range ~0–1).
        // Only used to trigger the workout countdown ("user is moving").
        movement = min(1.0, movement * 0.9 + Double(movementDelta) * 14.0)

        // ── ANGLE-BASED rep detection (the real fix) ─────────────────
        // Random body movement no longer counts. The user must produce a
        // real flexion-then-extension cycle of the relevant joint.
        let lowerEx = exercise.lowercased()
        let didRep: Bool
        if lowerEx.contains("push") || lowerEx.contains("dip") {
            // PUSH-UP — STRICT detection. Three signatures must hold:
            //   (1) Body is in plank position (shoulders and hips at similar
            //       Y, indicating horizontal body — not standing).
            //   (2) Both arms flex symmetrically (left + right elbow angles
            //       within 35° of each other).
            //   (3) Torso actually descends during the rep (shoulder Y
            //       moves meaningfully between extended and flexed states).
            didRep = detectPushUpRep(
                leftShoulder: leftS, rightShoulder: rightS,
                leftElbow: le, rightElbow: re,
                leftWrist: lw, rightWrist: rw,
                leftHip: lh, rightHip: rh,
                shoulderY: shoulderY
            )
        } else if lowerEx.contains("squat") || lowerEx.contains("lunge") {
            // Precise knee-angle detection WHEN the legs are visible. If the
            // camera can't see knees + ankles (a partial / upper-body-only
            // view), fall back to shoulder vertical travel so the rep STILL
            // counts — the user asked: even without the full body in frame,
            // attempt to count and judge whether they're doing one.
            // Knee just needs to be visible — don't also demand a confident
            // ankle (ankles are routinely the lowest-confidence joint indoors,
            // and requiring them dropped most squats onto the weak shoulder
            // fallback). The knee angle still uses the ankle when it's there.
            let leftLeg  = (lk?.confidence ?? 0) > 0.25
            let rightLeg = (rk?.confidence ?? 0) > 0.25
            if leftLeg || rightLeg {
                didRep = detectFlexionRep(
                    vertexL: lk, vertexR: rk,
                    aL: lh, aR: rh,
                    bL: la, bR: ra,
                    flexedBelow: 115, extendedAbove: 150,
                    minConfidence: 0.20
                )
            } else {
                didRep = detectGenericTorsoRep(currentY: shoulderY)
            }
        } else if lowerEx.contains("pull") || lowerEx.contains("chin") {
            // Pull-up: shoulder-vs-wrist Y delta. Hanging = shoulders far
            // below wrists. Pulled up = shoulders near wrists.
            didRep = detectPullUpRep(shoulderY: shoulderY,
                                     lw: lw, rw: rw)
        } else if lowerEx.contains("plank") {
            // Static hold — there are no "reps" to count.
            didRep = false
        } else if (lowerEx.contains("leg raise") || lowerEx.contains("leg lift")
                    || lowerEx.contains("knee raise") || lowerEx.contains("flutter")
                    || lowerEx.contains("scissor") || lowerEx.contains("toes to bar")
                    || lowerEx.contains("reverse crunch") || lowerEx.contains("v-up")
                    || lowerEx.contains("tuck-up") || lowerEx.contains("jackknife")
                    || lowerEx.contains("knee tuck") || lowerEx.contains("dragon flag"))
                   && !lowerEx.contains("standing") {
            // LEG RAISE family — torso fixed, legs swing up toward vertical.
            // Primary signal: HIP angle (shoulder-hip-ankle) cycling
            // extended (legs in line) -> flexed (legs up) -> extended.
            // Fallback for flutter/scissor: ankle-Y travel vs hip-Y.
            // ("Plank With Leg Lift" matched the plank branch above; "Standing
            //  Oblique Knee Raise" is excluded by !contains("standing").)
            didRep = detectLegRaiseRep(
                leftShoulder: leftS, rightShoulder: rightS,
                leftHip: lh, rightHip: rh,
                leftAnkle: la, rightAnkle: ra
            )
        } else if (lowerEx.contains("sit-up") || lowerEx.contains("sit up")
                    || lowerEx.contains("situp") || lowerEx.contains("crunch"))
                   && !lowerEx.contains("reverse") {
            // SIT-UP / CRUNCH — the torso folds up toward the thighs. Primary
            // signal: HIP angle (shoulder-hip-knee) cycling extended (lying flat)
            // -> flexed (curled up) -> extended. These previously had NO detector
            // and fell through to the weak shoulder-travel path, so small crunches
            // counted nothing. When hips/knees aren't visible, fall back to torso
            // travel (a full sit-up moves the shoulders a lot).
            let hipKneeVisible = ((lh?.confidence ?? 0) > 0.20 && (lk?.confidence ?? 0) > 0.20)
                               || ((rh?.confidence ?? 0) > 0.20 && (rk?.confidence ?? 0) > 0.20)
            if hipKneeVisible {
                didRep = detectFlexionRep(
                    vertexL: lh, vertexR: rh,
                    aL: leftS, aR: rightS,
                    bL: lk, bR: rk,
                    flexedBelow: 100, extendedAbove: 140,
                    minConfidence: 0.18
                )
            } else {
                didRep = detectGenericTorsoRep(currentY: shoulderY)
            }
        } else if lowerEx.contains("jumping jack") || lowerEx.contains("star jump")
                    || lowerEx.contains("jack") || lowerEx.contains("arm circle")
                    || lowerEx.contains("arm raise") || lowerEx.contains("lateral raise")
                    || lowerEx.contains("front raise") || lowerEx.contains("overhead")
                    || lowerEx.contains("shoulder press") || lowerEx.contains("press up")
                    || lowerEx.contains("y raise") || lowerEx.contains("snow angel")
                    || lowerEx.contains("reach") {
            // ARM-DRIVEN moves (jumping jacks, arm raises, presses) — the arms
            // swing through a big vertical range while the SHOULDERS barely move,
            // so the shoulder-Y detector counted nothing. Track the WRISTS.
            let wristY: CGFloat
            if let lw, lw.confidence > 0.15, let rw, rw.confidence > 0.15 {
                wristY = (lw.location.y + rw.location.y) / 2
            } else if let lw, lw.confidence > 0.15 {
                wristY = lw.location.y
            } else if let rw, rw.confidence > 0.15 {
                wristY = rw.location.y
            } else {
                wristY = shoulderY   // wrists not visible — fall back to torso
            }
            didRep = detectGenericTorsoRep(currentY: wristY)
        } else {
            // Any other move (burpees, mountain climbers, thrusters, etc.) —
            // count on a genuine torso swing. Lenient amplitude (see
            // detectGenericTorsoRep) so real movement always registers.
            didRep = detectGenericTorsoRep(currentY: shoulderY)
        }

        // Form hints — simple heuristics. Refined per exercise.
        let hints = computeHints(exercise: exercise,
                                 leftShoulder: leftS, rightShoulder: rightS,
                                 leftElbow: le, rightElbow: re,
                                 leftWrist: lw, rightWrist: rw,
                                 leftHip: lh, rightHip: rh,
                                 leftKnee: lk, rightKnee: rk,
                                 leftAnkle: la, rightAnkle: ra)

        // ── Build the joint map for the skeleton overlay ───────────────
        // We collect every joint with confidence ≥ 0.30 (was 0.25 — tighter
        // confidence floor so noisy detections don't draw glitchy dots).
        var joints: [PoseJoint: CGPoint] = [:]
        func add(_ p: VNRecognizedPoint?, as key: PoseJoint, minConf: Float = 0.30) {
            guard let p, p.confidence >= minConf else { return }
            joints[key] = CGPoint(x: p.location.x, y: p.location.y)
        }
        let nose = recognized[.nose]
        let neck = recognized[.neck]
        add(nose,     as: .nose)
        add(neck,     as: .neck)
        add(leftS,    as: .leftShoulder)
        add(rightS,   as: .rightShoulder)
        add(le,       as: .leftElbow)
        add(re,       as: .rightElbow)
        add(lw,       as: .leftWrist)
        add(rw,       as: .rightWrist)
        add(lh,       as: .leftHip)
        add(rh,       as: .rightHip)
        add(lk,       as: .leftKnee)
        add(rk,       as: .rightKnee)
        add(la,       as: .leftAnkle)
        add(ra,       as: .rightAnkle)

        // ── DERIVED midpoints — user wanted points along the limbs ──
        // Vision body-pose only exposes endpoint joints (shoulder, elbow,
        // wrist, etc.). The user asked for points on the bicep, forearm,
        // thigh, shin and a centered head point. We compute each as the
        // midpoint of the two adjacent endpoints when both are visible.
        func midpoint(_ a: PoseJoint, _ b: PoseJoint, into key: PoseJoint) {
            if let pa = joints[a], let pb = joints[b] {
                joints[key] = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
            }
        }
        midpoint(.leftShoulder,  .leftElbow,  into: .leftBicep)
        midpoint(.rightShoulder, .rightElbow, into: .rightBicep)
        midpoint(.leftElbow,     .leftWrist,  into: .leftForearm)
        midpoint(.rightElbow,    .rightWrist, into: .rightForearm)
        midpoint(.leftHip,       .leftKnee,   into: .leftThigh)
        midpoint(.rightHip,      .rightKnee,  into: .rightThigh)
        midpoint(.leftKnee,      .leftAnkle,  into: .leftShin)
        midpoint(.rightKnee,     .rightAnkle, into: .rightShin)
        // Head point — midpoint between nose and neck for a centered head dot.
        midpoint(.nose,          .neck,       into: .head)

        // ── Skeleton color gate — turn green at ~50% accuracy ─────────
        // The skeleton color is now purely visual feedback (the rep
        // gate is enforced by the biomechanical validators upstream).
        // 50% (7/14 endpoint joints) is enough to draw a credible
        // skeleton, even when the user moves out of the camera's optimal
        // range mid-rep. This stops the red flicker during the descent
        // phase of push-ups.
        let endpointJointCount = joints.filter { !$0.key.isDerived }.count
        let formIsGood = (hints.count <= 1) && endpointJointCount >= 7

        return PoseDetectionResult(
            personDetected: true,
            smoothedShoulderY: shoulderY,
            motionConfidence: movement,
            didCompleteRep: didRep,
            hints: hints,
            joints: joints,
            formIsGood: formIsGood
        )
    }

    // MARK: - Push-up specific detection (strict)
    //
    // A real push-up satisfies THREE signatures simultaneously:
    //   1. PLANK BODY — shoulders and hips at similar Y (body horizontal).
    //      If the user is standing up, |shoulderY - hipY| is large; we
    //      reject those frames entirely.
    //   2. SYMMETRIC ARMS — left and right elbow angles within ~35° of
    //      each other throughout the cycle. Asymmetric one-arm movements
    //      don't count.
    //   3. TORSO MOTION — the shoulders actually descend then rise during
    //      the rep. Random arm waving doesn't move the torso at all.
    //
    // Combined, these three filters reject "any movement that flexes the
    // elbow" — only a real push-up gets through.
    private func detectPushUpRep(
        leftShoulder: VNRecognizedPoint, rightShoulder: VNRecognizedPoint,
        leftElbow: VNRecognizedPoint?, rightElbow: VNRecognizedPoint?,
        leftWrist: VNRecognizedPoint?, rightWrist: VNRecognizedPoint?,
        leftHip: VNRecognizedPoint?, rightHip: VNRecognizedPoint?,
        shoulderY: CGFloat
    ) -> Bool {
        // MINIMAL VALIDATION. User explicit ask: "just track the arms.
        // Every time I do a push-up, count it." Strip the strict posture
        // and torso-motion checks — they were rejecting real reps when
        // the camera couldn't see the user's full body, hips, or when
        // smoothing ate the torso signal.
        //
        // We still keep two cheap sanity gates so random arm-waving
        // while standing doesn't count:
        //   (1) Both arms tracked (left + right elbow angles available),
        //       roughly symmetric — rules out one-arm gestures.
        //   (2) Wrists not CLEARLY above shoulders — rules out standing
        //       arm-curl motions (in a curl, wrists end up at chest/face
        //       level which is at or above shoulder Y).

        // Both arms must be computable.
        guard let leftAngle  = angleAt(vertex: leftElbow,  a: leftShoulder,  b: leftWrist,  minConfidence: 0.20),
              let rightAngle = angleAt(vertex: rightElbow, a: rightShoulder, b: rightWrist, minConfidence: 0.20) else {
            return false
        }
        // Symmetric — both arms moving together (within 60°). A bit looser so
        // one noisy arm doesn't drop the whole rep.
        guard abs(leftAngle - rightAngle) < 60 else { return false }
        let elbowAngle = smoothAngle((leftAngle + rightAngle) / 2)

        // Wrists below (or roughly at) shoulder level. Vision Y: 0 = bottom.
        // wristY > shoulderY + 0.05 means wrists ABOVE shoulders ⇒ arm-curl
        // position, not push-up. Reject.
        if let lw = leftWrist, lw.confidence > 0.20,
           let rw = rightWrist, rw.confidence > 0.20 {
            let wristY = (lw.location.y + rw.location.y) / 2
            if wristY > shoulderY + 0.05 { return false }
        }

        // State machine — elbows flex from extended (>=145°) to deep
        // flexion (<=110°) and back. Thresholds slightly loosened so
        // close-to-perfect reps register even with smoothing noise.
        let now = Date().timeIntervalSince1970
        guard now - lastRepAt > 0.6 else { return false }

        switch angleState {
        case .extended:
            // Easier to reach the "down" state (115° instead of 110°).
            if elbowAngle <= 115 {
                angleState = .flexed
            }
            return false
        case .flexed:
            // Don't demand a full lockout — most people peak around 135–140°,
            // and EMA smoothing lags the true angle, so 145° often never
            // re-armed the next rep. 138° still leaves a safe ~23° hysteresis gap.
            if elbowAngle >= 138 {
                angleState = .extended
                lastRepAt = now
                return true
            }
            return false
        }
    }

    // MARK: - Joint-angle rep detection
    //
    // detectFlexionRep counts a rep when the average of (left, right) joint
    // angles cycles through (flexed → extended). The angle is computed at
    // a vertex joint (e.g. elbow) between two adjacent joints (e.g.
    // shoulder + wrist).
    //
    // - vertexL/R : the joint AT THE ANGLE (elbow for push-ups, knee for squats)
    // - aL/R      : one side of the angle (shoulder for push-up elbow)
    // - bL/R      : the other side (wrist for push-up elbow)
    // - flexedBelow : threshold (degrees) for the deep position
    // - extendedAbove : threshold (degrees) for the top position
    //
    // We average left + right when both are visible. If only one side is
    // visible at sufficient confidence, we use that one. Otherwise, no rep.
    private func detectFlexionRep(
        vertexL: VNRecognizedPoint?, vertexR: VNRecognizedPoint?,
        aL: VNRecognizedPoint?,      aR: VNRecognizedPoint?,
        bL: VNRecognizedPoint?,      bR: VNRecognizedPoint?,
        flexedBelow: Double, extendedAbove: Double,
        minConfidence: Float
    ) -> Bool {
        // Compute angle for each side that we can see
        let leftAngle  = angleAt(vertex: vertexL, a: aL, b: bL, minConfidence: minConfidence)
        let rightAngle = angleAt(vertex: vertexR, a: aR, b: bR, minConfidence: minConfidence)

        let rawAngle: Double
        switch (leftAngle, rightAngle) {
        case let (l?, r?): rawAngle = (l + r) / 2
        case let (l?, nil): rawAngle = l
        case let (nil, r?): rawAngle = r
        default: return false   // not enough visibility — no signal
        }
        // EMA-smooth before the threshold checks → far fewer phantom/missed reps.
        let angle = smoothAngle(rawAngle)

        let now = Date().timeIntervalSince1970
        // Debounce: minimum 0.5 s between reps. Push-ups can be fast but
        // not faster than 2/sec for a real human form.
        guard now - lastRepAt > 0.5 else { return false }

        switch angleState {
        case .extended:
            // Waiting for user to flex (bend the elbow / knee)
            if angle <= flexedBelow {
                angleState = .flexed
            }
            return false
        case .flexed:
            // Waiting for user to extend back
            if angle >= extendedAbove {
                angleState = .extended
                lastRepAt = now
                return true       // ← REAL REP
            }
            return false
        }
    }

    /// Pull-up rep — counts when the shoulders rise from "well below wrists"
    /// up close to wrist level and back down. Requires a clear ~12% swing.
    private func detectPullUpRep(shoulderY: CGFloat,
                                 lw: VNRecognizedPoint?, rw: VNRecognizedPoint?) -> Bool {
        // Hands near a bar are often low-confidence or partly out of frame —
        // one confident wrist is enough (was: both required at 0.25).
        let wristY: CGFloat
        if let lw, lw.confidence > 0.18, let rw, rw.confidence > 0.18 {
            wristY = (lw.location.y + rw.location.y) / 2
        } else if let lw, lw.confidence > 0.18 {
            wristY = lw.location.y
        } else if let rw, rw.confidence > 0.18 {
            wristY = rw.location.y
        } else {
            return false
        }
        // Vision Y: 1.0 = top. wristY - shoulderY: positive = shoulders below
        // wrists (hanging position).
        let delta = wristY - shoulderY

        let now = Date().timeIntervalSince1970
        guard now - lastRepAt > 0.6 else { return false }

        // State semantics for pull-ups: .extended = hanging (delta large),
        // .flexed = pulled up (delta near 0). Thresholds in normalized frame Y.
        switch angleState {
        case .extended:
            if delta < 0.07 { angleState = .flexed }   // pulled up (a bit easier)
            return false
        case .flexed:
            if delta > 0.14 {                           // back to a clear hang
                angleState = .extended
                lastRepAt = now
                return true
            }
            return false
        }
    }

    // MARK: - Leg-raise detection
    //
    // Leg raises keep the TORSO fixed and swing the LEGS up. Primary signal is
    // the HIP angle (shoulder-hip-ankle): ~180° legs-down (extended) -> <=120°
    // legs-up (flexed) -> back = 1 rep. Average both sides; use whichever single
    // side is visible (partial / side-on views are common lying down). Flutter/
    // scissor kicks barely cycle the hip angle, so when no hip angle is
    // computable we fall back to ankle-Y travel relative to hip-Y with an
    // amplitude envelope. Vision Y: 0 = bottom, 1 = top.
    private var legRaiseEnvelope: [CGFloat] = []
    private func detectLegRaiseRep(
        leftShoulder: VNRecognizedPoint, rightShoulder: VNRecognizedPoint,
        leftHip: VNRecognizedPoint?, rightHip: VNRecognizedPoint?,
        leftAnkle: VNRecognizedPoint?, rightAnkle: VNRecognizedPoint?
    ) -> Bool {
        let now = Date().timeIntervalSince1970

        // ── PRIMARY: hip angle (shoulder-hip-ankle) per visible side ──
        let leftHipAngle  = angleAt(vertex: leftHip,  a: leftShoulder,  b: leftAnkle,  minConfidence: 0.20)
        let rightHipAngle = angleAt(vertex: rightHip, a: rightShoulder, b: rightAnkle, minConfidence: 0.20)
        let hipAngle: Double?
        switch (leftHipAngle, rightHipAngle) {
        case let (l?, r?): hipAngle = (l + r) / 2
        case let (l?, nil): hipAngle = l
        case let (nil, r?): hipAngle = r
        default: hipAngle = nil
        }

        if let raw = hipAngle {
            let angle = smoothAngle(raw)   // EMA-smooth the hip angle
            guard now - lastRepAt > 0.5 else { return false }
            switch angleState {
            case .extended:
                if angle <= 120 { angleState = .flexed }   // legs lifted up
                return false
            case .flexed:
                if angle >= 148 {                           // legs back down (don't demand fully flat)
                    angleState = .extended
                    lastRepAt = now
                    return true
                }
                return false
            }
        }

        // ── FALLBACK: ankle-Y travel vs hip-Y (flutter / scissor kicks) ──
        let hipY: CGFloat?
        if let lh = leftHip, lh.confidence > 0.20, let rh = rightHip, rh.confidence > 0.20 {
            hipY = (lh.location.y + rh.location.y) / 2
        } else if let lh = leftHip, lh.confidence > 0.20 {
            hipY = lh.location.y
        } else if let rh = rightHip, rh.confidence > 0.20 {
            hipY = rh.location.y
        } else { hipY = nil }

        let ankleY: CGFloat?
        if let la = leftAnkle, la.confidence > 0.20, let ra = rightAnkle, ra.confidence > 0.20 {
            ankleY = (la.location.y + ra.location.y) / 2
        } else if let la = leftAnkle, la.confidence > 0.20 {
            ankleY = la.location.y
        } else if let ra = rightAnkle, ra.confidence > 0.20 {
            ankleY = ra.location.y
        } else { ankleY = nil }

        guard let hy = hipY, let ay = ankleY else { return false }
        let delta = ay - hy                                  // larger = legs higher

        legRaiseEnvelope.append(delta)
        if legRaiseEnvelope.count > 30 { legRaiseEnvelope.removeFirst() }
        guard legRaiseEnvelope.count >= 14 else { return false }   // start counting sooner
        let minD = legRaiseEnvelope.min() ?? 0
        let maxD = legRaiseEnvelope.max() ?? 0
        let amp = maxD - minD
        guard amp > 0.07 else { return false }               // need a real swing (a bit smaller OK)
        let mid = (minD + maxD) / 2
        let low = mid - amp * 0.30
        let high = mid + amp * 0.30

        guard now - lastRepAt > 0.5 else { return false }
        switch angleState {
        case .extended:
            if delta > high { angleState = .flexed }          // legs up
            return false
        case .flexed:
            if delta < low {                                  // legs back down
                angleState = .extended
                lastRepAt = now
                return true
            }
            return false
        }
    }

    /// Generic torso swing — requires 8% peak-to-peak shoulder-Y swing per
    /// cycle so head bobbing doesn't trigger it.
    private var torsoHistory: [CGFloat] = []
    private var torsoState: AngleState = .extended
    private func detectGenericTorsoRep(currentY: CGFloat) -> Bool {
        torsoHistory.append(currentY)
        if torsoHistory.count > 30 { torsoHistory.removeFirst() }
        guard torsoHistory.count >= 14 else { return false }   // start counting sooner

        let minY = torsoHistory.min() ?? 0
        let maxY = torsoHistory.max() ?? 0
        let amplitude = maxY - minY
        // Lenient by design: ~3% of frame-height swing counts a rep. This is the
        // catch-all for crunches/burpees/mountain-climbers where the tracked joint
        // barely moves vertically; the ±30% hysteresis band + 0.5s cooldown below
        // still reject head-bobbing and noise.
        guard amplitude > 0.03 else { return false }

        let mid = (minY + maxY) / 2
        let low = mid - amplitude * 0.30
        let high = mid + amplitude * 0.30

        let now = Date().timeIntervalSince1970
        guard now - lastRepAt > 0.5 else { return false }

        switch torsoState {
        case .extended:
            if currentY < low { torsoState = .flexed }
            return false
        case .flexed:
            if currentY > high {
                torsoState = .extended
                lastRepAt = now
                return true
            }
            return false
        }
    }

    /// Angle at `vertex` formed by `a` and `b`, in degrees. Returns nil if
    /// any of the three joints has insufficient confidence.
    private func angleAt(
        vertex: VNRecognizedPoint?, a: VNRecognizedPoint?, b: VNRecognizedPoint?,
        minConfidence: Float
    ) -> Double? {
        guard let v = vertex, v.confidence >= minConfidence,
              let a = a, a.confidence >= minConfidence,
              let b = b, b.confidence >= minConfidence else { return nil }
        let va = (x: a.location.x - v.location.x, y: a.location.y - v.location.y)
        let vb = (x: b.location.x - v.location.x, y: b.location.y - v.location.y)
        let dot = va.x * vb.x + va.y * vb.y
        let magA = sqrt(va.x * va.x + va.y * va.y)
        let magB = sqrt(vb.x * vb.x + vb.y * vb.y)
        guard magA > 0.0001, magB > 0.0001 else { return nil }
        let cosAng = max(-1, min(1, dot / (magA * magB)))
        return acos(cosAng) * 180.0 / .pi
    }

    private func computeHints(exercise: String,
                              leftShoulder: VNRecognizedPoint, rightShoulder: VNRecognizedPoint,
                              leftElbow: VNRecognizedPoint?, rightElbow: VNRecognizedPoint?,
                              leftWrist: VNRecognizedPoint?, rightWrist: VNRecognizedPoint?,
                              leftHip: VNRecognizedPoint?, rightHip: VNRecognizedPoint?,
                              leftKnee: VNRecognizedPoint?, rightKnee: VNRecognizedPoint?,
                              leftAnkle: VNRecognizedPoint?, rightAnkle: VNRecognizedPoint?) -> [String] {
        var hints: [String] = []
        let lower = exercise.lowercased()

        // Shoulder level check — uneven shoulders flag bad alignment
        let shoulderTilt = abs(leftShoulder.location.y - rightShoulder.location.y)
        if shoulderTilt > 0.06 {
            hints.append("Level your shoulders")
        }

        // ── Push-up specific coaching ────────────────────────────────
        if lower.contains("push") || lower.contains("plank") || lower.contains("dip") {
            // Hip alignment (existing).
            if let lh = leftHip, let rh = rightHip, lh.confidence > 0.3, rh.confidence > 0.3 {
                let hipY = (lh.location.y + rh.location.y) / 2
                let shoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
                let drop = shoulderY - hipY
                if drop > 0.10 { hints.append("Drop your hips — keep your back straight") }
                if drop < -0.10 { hints.append("Don't pike your hips — flatten your body") }
            }
            // Knee push-up detection — if knees are at roughly the same Y
            // as wrists (both on the ground) it means the user is doing
            // a girl push-up / knee push-up. Coach: extend the legs.
            if let lk = leftKnee, let rk = rightKnee,
               let lw = leftWrist, let rw = rightWrist,
               lk.confidence > 0.30, rk.confidence > 0.30,
               lw.confidence > 0.30, rw.confidence > 0.30 {
                let kneeY = (lk.location.y + rk.location.y) / 2
                let wristY = (lw.location.y + rw.location.y) / 2
                // Knees almost as low as wrists → knee push-up posture.
                // Real push-up: knees are MUCH higher (legs extended back).
                if abs(kneeY - wristY) < 0.10 {
                    hints.append("Extend your legs — do a full push-up, not a knee push-up")
                }
            }
            // Asymmetric arm check — both arms should bend together.
            if let leftAng = angleAt(vertex: leftElbow,  a: leftShoulder,  b: leftWrist,  minConfidence: 0.30),
               let rightAng = angleAt(vertex: rightElbow, a: rightShoulder, b: rightWrist, minConfidence: 0.30) {
                if abs(leftAng - rightAng) > 50 {
                    hints.append("Use both arms together")
                }
            }
        }

        // ── Squat specific coaching ──────────────────────────────────
        if lower.contains("squat") || lower.contains("lunge") {
            // Knees should be flexing the same amount on each side.
            if let lk = leftKnee, let rk = rightKnee,
               let lh = leftHip, let rh = rightHip,
               let la = leftAnkle, let ra = rightAnkle,
               lk.confidence > 0.30, rk.confidence > 0.30 {
                if let leftAng = angleAt(vertex: lk, a: lh, b: la, minConfidence: 0.30),
                   let rightAng = angleAt(vertex: rk, a: rh, b: ra, minConfidence: 0.30) {
                    if abs(leftAng - rightAng) > 40 {
                        hints.append("Keep both knees moving evenly")
                    }
                }
            }
        }

        return hints
    }
}
