import Foundation

// MARK: - On-device exercise coaching + camera onboarding
//
// Single source of truth for two things the Live workout needs:
//   1. Is this movement AUTO-TRACKED by the on-device skeleton (rep-counted),
//      or is it a TIMED HOLD?
//   2. The per-exercise "onboarding" — exactly how to place the phone and frame
//      yourself so the Vision pose detector can actually see and count the move.
//
// Crucially, the classification below mirrors EXACTLY the name-token routing in
// `PoseDetectionService.detect()` (and `LiveWorkoutView.isHoldByName`). That is
// deliberate: the catalog (`WorkoutLibrary`) only ships exercises whose names
// route to one of these reliable detectors, so the guidance we show the user
// always matches what the detector is expecting to see. If you add a token to
// the detector, add it here too.

enum TrackedMovement: String {
    case pushup        // elbow-angle, ground, side-on
    case squat         // knee-angle, standing, facing
    case pullup        // wrist↔shoulder delta, on a bar
    case legRaise      // hip-angle / leg swing, lying, side-on
    case armSwing      // wrist height, standing, facing
    case hold          // isometric — timed, no reps

    var title: String {
        switch self {
        case .pushup:   return "Push / Dip"
        case .squat:    return "Squat / Lunge"
        case .pullup:   return "Pull-up / Chin-up"
        case .legRaise: return "Core — Leg Raise"
        case .armSwing: return "Standing — Arms"
        case .hold:     return "Timed Hold"
        }
    }

    var symbol: String {
        switch self {
        case .pushup:   return "figure.strengthtraining.traditional"
        case .squat:    return "figure.cross.training"
        case .pullup:   return "figure.play"
        case .legRaise: return "figure.core.training"
        case .armSwing: return "figure.arms.open"
        case .hold:     return "timer"
        }
    }
}

struct ExerciseCoaching {
    let movement: TrackedMovement
    /// true = the skeleton counts reps; false = it's a timed hold (countdown).
    let isAutoCounted: Bool
    /// Where to put the phone.
    let cameraPlacement: String
    /// What must be visible in the frame.
    let framing: String
    /// 2–3 short setup bullets.
    let setupTips: [String]
    /// One line on how a rep / the hold is registered.
    let countingHint: String

    /// Classify an exercise by name — mirrors PoseDetectionService routing.
    /// Order matters: holds are checked first (a "Plank" is never a rep move),
    /// then the specialized rep detectors, then the standing arm-swing default.
    static func forExercise(named raw: String) -> ExerciseCoaching {
        let n = raw.lowercased()
        func has(_ s: String) -> Bool { n.contains(s) }

        // 1) Timed isometric holds (matches LiveWorkoutView.isHoldByName + the
        //    "plank" no-rep branch in PoseDetectionService).
        if has("plank") || has("hold") || has("wall sit") || has("dead hang")
            || has("hollow") || has("l-sit") || has("l sit") || has("superman")
            || has("wall squat") || has("isometric") || has("bridge hold") {
            return ExerciseCoaching(
                movement: .hold,
                isAutoCounted: false,
                cameraPlacement: "Prop your phone on the floor or a low shelf to your side, about 3–4 ft away.",
                framing: "Side-on — your whole body in the frame.",
                setupTips: [
                    "Get all the way into position before you start.",
                    "Hold steady and breathe — keep the shape until the timer hits zero."
                ],
                countingHint: "This is a timed hold — the on-screen timer counts down while you hold the position.")
        }

        // 2) Push-ups / dips — elbow-angle state machine, viewed from the side.
        if has("push") || has("dip") {
            return ExerciseCoaching(
                movement: .pushup,
                isAutoCounted: true,
                cameraPlacement: "Lay your phone on the floor, propped sideways against a wall, about 3–4 ft to your side.",
                framing: "Side-on — head, back and hips all in the frame.",
                setupTips: [
                    "Turn so the camera sees you from the side.",
                    "Keep your body in one straight line from head to heels."
                ],
                countingHint: "Counts one rep each time you lower your chest down and press back up.")
        }

        // 3) Squats / lunges — knee-angle state machine, viewed from the front.
        if has("squat") || has("lunge") {
            return ExerciseCoaching(
                movement: .squat,
                isAutoCounted: true,
                cameraPlacement: "Stand your phone upright 6–8 ft in front of you (on a chair or shelf), camera facing you.",
                framing: "Facing the camera — head all the way down to your feet.",
                setupTips: [
                    "Make sure your hips and knees are clearly visible.",
                    "Step back until your whole body fits in the frame."
                ],
                countingHint: "Counts one rep each time your knees bend down and straighten back up.")
        }

        // 4) Pull-ups / chin-ups — wrist↔shoulder delta, on a bar.
        if has("pull") || has("chin") {
            return ExerciseCoaching(
                movement: .pullup,
                isAutoCounted: true,
                cameraPlacement: "Set your phone facing your bar, 6–8 ft back, upright.",
                framing: "Facing the bar — your hanging body and both arms in the frame.",
                setupTips: [
                    "Your arms and shoulders must be visible at the top and bottom.",
                    "Light should be on you, not behind you."
                ],
                countingHint: "Counts one rep each time you pull your chin up toward the bar and lower all the way down.")
        }

        // 5) Core leg-raise family — hip-angle / leg-swing, lying side-on.
        if has("leg raise") || has("leg lift") || has("knee raise") || has("flutter")
            || has("scissor") || has("toes to bar") || has("reverse crunch") || has("v-up")
            || has("tuck-up") || has("jackknife") || has("knee tuck") || has("dragon flag") {
            return ExerciseCoaching(
                movement: .legRaise,
                isAutoCounted: true,
                cameraPlacement: "Lay your phone on the floor to your side, propped against a wall, about 3–4 ft away.",
                framing: "Side-on — your torso and legs in the frame as you lie down.",
                setupTips: [
                    "Lie sideways to the camera so it sees your legs rise and fall.",
                    "Clear the space around your legs."
                ],
                countingHint: "Counts one rep each time your legs raise up and lower back down.")
        }

        // 6) Standing arm-driven moves (jumping jacks, raises, presses) — wrist
        //    height tracking. Also the safe default for anything else.
        return ExerciseCoaching(
            movement: .armSwing,
            isAutoCounted: true,
            cameraPlacement: "Stand your phone upright 6–8 ft in front of you, camera facing you.",
            framing: "Facing the camera — your arms and upper body clearly in the frame.",
            setupTips: [
                "Keep your hands in view through the whole movement.",
                "Step back so your arms stay in frame when they're raised."
            ],
            countingHint: "Counts one rep each time your arms travel up and come back down.")
    }
}
