import Foundation

// MARK: - Built-in, on-device exercise library
//
// A curated catalog of exercises that ships INSIDE the app — no network, no AI.
// Powers the free "Custom Workout" builder and its library-backed Swap.
//
// CURATION RULE (important): every exercise here is one the on-device skeleton
// (Apple Vision, PoseDetectionService) can actually track. Its NAME routes to a
// reliable rep detector — "push"/"dip" (elbow angle), "squat"/"lunge" (knee
// angle), "pull"/"chin" (wrist↔shoulder), the leg-raise family (hip angle), or
// standing arm-swings (wrist height) — OR to a timed isometric hold ("plank",
// "wall sit", "hold", "dead hang", "hollow", "superman", "bridge hold").
//
// We deliberately do NOT ship exercises the camera can't read (bench press,
// machine work, Olympic lifts, carries, cable moves, etc.). Each exercise's
// camera-setup onboarding lives in `ExerciseCoaching`, keyed off the same name
// tokens — so what we tell the user matches what the detector expects to see.
//
// Reps are single integers ("12") or holds ("30 sec") only — matching the
// LiveWorkoutView / EditExerciseSheet parsers (no ranges).

enum MuscleGroup: String, CaseIterable, Identifiable, Hashable {
    case chest, back, legs, shoulders, arms, core, cardio, fullBody

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest:     return "Chest"
        case .back:      return "Back"
        case .legs:      return "Legs"
        case .shoulders: return "Shoulders"
        case .arms:      return "Arms"
        case .core:      return "Core"
        case .cardio:    return "Cardio"
        case .fullBody:  return "Full Body"
        }
    }

    var icon: String {
        switch self {
        case .chest:     return "figure.strengthtraining.traditional"
        case .back:      return "figure.strengthtraining.functional"
        case .legs:      return "figure.run"
        case .shoulders: return "figure.arms.open"
        case .arms:      return "dumbbell.fill"
        case .core:      return "figure.core.training"
        case .cardio:    return "heart.fill"
        case .fullBody:  return "figure.mixed.cardio"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Hashable {
    case bodyweight, dumbbell, barbell, machine, cable, kettlebell, none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyweight: return "Bodyweight"
        case .dumbbell:   return "Dumbbell"
        case .barbell:    return "Barbell"
        case .machine:    return "Machine"
        case .cable:      return "Cable"
        case .kettlebell: return "Kettlebell"
        case .none:       return "No equipment"
        }
    }

    var icon: String {
        switch self {
        case .bodyweight: return "figure.stand"
        case .dumbbell:   return "dumbbell.fill"
        case .barbell:    return "figure.strengthtraining.traditional"
        case .machine:    return "gearshape.fill"
        case .cable:      return "cable.connector"
        case .kettlebell: return "figure.strengthtraining.functional"
        case .none:       return "bolt.fill"
        }
    }
}

struct LibraryExercise: Identifiable, Hashable {
    var id: String { name }              // names are unique within the library
    let name: String
    let muscleGroup: MuscleGroup
    let equipment: Equipment
    let defaultSets: Int                 // rounds (UI label: "rounds")
    let defaultReps: String              // single int "12" or hold "30 sec"
    let defaultRestSeconds: Int
    let isTimed: Bool                    // plank / wall sit / hold
    let formCue: String?                 // short, static (no AI)

    var symbol: String { WorkoutLibrary.symbol(for: name, group: muscleGroup, equipment: equipment) }

    /// On-device tracking + camera-setup guidance for this exercise (keyed off
    /// the name, mirroring the PoseDetectionService routing).
    var coaching: ExerciseCoaching { ExerciseCoaching.forExercise(named: name) }

    /// True when the skeleton auto-counts reps; false for timed holds.
    var isAutoCounted: Bool { coaching.isAutoCounted }

    /// Bridge into the shared plan model used by TodayWorkoutSheet + Live mode.
    func asWorkoutExercise() -> WorkoutExercise {
        WorkoutExercise(name: name, sets: defaultSets, reps: defaultReps,
                        restSeconds: defaultRestSeconds, notes: formCue)
    }
}

enum WorkoutLibrary {

    // Terse factory so the catalog stays readable.
    private static func ex(_ name: String, _ g: MuscleGroup, _ e: Equipment,
                           sets: Int = 3, reps: String, rest: Int = 60,
                           timed: Bool = false, cue: String? = nil) -> LibraryExercise {
        LibraryExercise(name: name, muscleGroup: g, equipment: e,
                        defaultSets: sets, defaultReps: reps, defaultRestSeconds: rest,
                        isTimed: timed, formCue: cue)
    }

    /// A movement-specific SF Symbol for an exercise. Keyword-first: the name
    /// drives a distinct icon for each *type* of workout (run vs jump-rope vs
    /// boxing vs bike vs rower vs carry vs push vs core …) so the library and
    /// builder don't show one generic icon per muscle group — every cardio move
    /// used to share `heart.fill`. Falls back to the muscle-group icon when the
    /// name doesn't reveal a more specific movement.
    static func symbol(for name: String, group: MuscleGroup, equipment: Equipment) -> String {
        let n = name.lowercased()
        func has(_ s: String) -> Bool { n.contains(s) }

        // ── Conditioning / cardio movement types (most visually specific) ──
        if has("jump rope") || has("jumprope") || has("double-under") || has("double under") { return "figure.jumprope" }
        if has("boxing") || has("shadow box") || has("jab") || has("uppercut") { return "figure.boxing" }
        if has("kickbox") || has("martial") || has("muay") || has("karate") { return "figure.kickboxing" }
        if has("rower") || has("rowing machine") || has("ski erg") || has("ski-erg") { return "figure.rower" }
        if has("bike") || has("cycle") || has("cycling") { return "figure.indoor.cycle" }
        if has("elliptical") { return "figure.elliptical" }
        if has("stair") { return "figure.stair.stepper" }
        if has("burpee") || has("mountain climber") || has("squat thrust") || has("sprawl")
            || has("devil press") || has("man maker") { return "figure.highintensity.intervaltraining" }
        if has("rock climb") || has("wall climb") { return "figure.climbing" }
        if has("walk") || has("march") { return "figure.walk" }
        if has("carry") { return "figure.walk" }
        if has("sprint") || has("treadmill") || has("run") || has("jog") { return "figure.run" }
        if has("jump") || has("hop") || has("bound") || has("skater") || has("skip")
            || has("jack") || has("plyo") || has("pop squat") || has("frog") || has("heisman")
            || has("agility") { return "figure.mixed.cardio" }
        if has("battle rope") || has("sled") || has("yoke") || has("swing") || has("snatch")
            || has("clean") || has("jerk") || has("thruster") || has("turkish") || has("kettlebell")
            || has("wall ball") || has("slam") || has("complex") || has("get-up") || has("halo") { return "figure.strengthtraining.functional" }

        // ── Strength movement types ──
        if has("push-up") || has("pushup") || has("push up") || has("dip")
            || has("bench") || has("chest press") || has("flye") || has("fly") { return "figure.strengthtraining.traditional" }
        if has("plank") || has("crunch") || has("sit-up") || has("situp") || has("sit up")
            || has("oblique") || has("leg raise") || has("v-up") || has("hollow") || has("bridge")
            || has("russian twist") || has("superman") || has("dead bug") || has("bird dog")
            || has("windmill") || has("side bend") { return "figure.core.training" }
        if has("curl") || has("tricep") || has("extension") || has("kickback") || has("skull") { return "dumbbell.fill" }
        if has("press") || has("raise") || has("shoulder") || has("delt") || has("overhead")
            || has("arnold") || has("upright") { return "figure.arms.open" }
        if has("yoga") || has("stretch") || has("mobility") || has("cooldown") || has("foam") { return "figure.cooldown" }

        // ── Fallback: the muscle-group icon ──
        return group.icon
    }

    // Every entry below is auto-trackable by the on-device skeleton. Grouped by
    // the detector its name routes to (see ExerciseCoaching / PoseDetectionService).
    static let all: [LibraryExercise] = [

        // ── PUSH-UPS & DIPS — elbow-angle, viewed side-on ──────────────
        ex("Push-ups", .chest, .bodyweight, reps: "12", cue: "Body in a straight line, lower your chest to the floor"),
        ex("Knee Push-ups", .chest, .bodyweight, reps: "12", cue: "Knees down, still keep a straight back — easier scaling"),
        ex("Incline Push-ups", .chest, .bodyweight, reps: "12", cue: "Hands on a bench or step — easier on the chest"),
        ex("Wide Push-ups", .chest, .bodyweight, reps: "12", cue: "Hands wider than shoulders, more chest"),
        ex("Decline Push-ups", .chest, .bodyweight, reps: "10", cue: "Feet up on a step — more upper-chest and shoulders"),
        ex("Diamond Push-ups", .arms, .bodyweight, reps: "10", cue: "Hands together under your chest — hits the triceps"),
        ex("Pike Push-ups", .shoulders, .bodyweight, reps: "10", cue: "Hips high, press your head toward the floor — shoulders"),
        ex("Tricep Dips", .arms, .bodyweight, reps: "12", cue: "On a chair or bench, lower until elbows hit 90°"),
        ex("Bench Dips", .arms, .bodyweight, reps: "12", cue: "Hands on a bench behind you, dip straight down"),

        // ── SQUATS & LUNGES — knee-angle, viewed facing the camera ─────
        ex("Bodyweight Squats", .legs, .bodyweight, reps: "15", cue: "Sit back, knees track over toes, chest up"),
        ex("Sumo Squats", .legs, .bodyweight, reps: "15", cue: "Wide stance, toes out, drive through the heels"),
        ex("Jump Squats", .legs, .bodyweight, reps: "12", cue: "Squat, then explode up — land soft and reset"),
        ex("Forward Lunges", .legs, .bodyweight, reps: "12", cue: "Step forward, both knees to 90°, alternate legs (12 total)"),
        ex("Reverse Lunges", .legs, .bodyweight, reps: "12", cue: "Step back into the lunge — easier on the knees (12 total)"),
        ex("Walking Lunges", .legs, .bodyweight, reps: "12", cue: "Lunge forward and walk through, alternating (12 total)"),
        ex("Bulgarian Split Squats", .legs, .bodyweight, reps: "10", cue: "Rear foot on a bench, drop straight down (per leg)"),
        ex("Goblet Squats", .legs, .dumbbell, reps: "12", cue: "Hold a weight at your chest, squat deep and upright"),

        // ── PULL-UPS & CHIN-UPS — wrist↔shoulder, on a bar ─────────────
        ex("Pull-ups", .back, .bodyweight, reps: "8", rest: 75, cue: "Overhand grip, pull your chin over the bar"),
        ex("Chin-ups", .back, .bodyweight, reps: "8", rest: 75, cue: "Underhand grip — more biceps, pull all the way up"),
        ex("Wide-Grip Pull-ups", .back, .bodyweight, reps: "6", rest: 75, cue: "Wider than shoulders — hits the lats harder"),
        ex("Neutral-Grip Pull-ups", .back, .bodyweight, reps: "8", rest: 75, cue: "Palms facing each other — easiest on the shoulders"),
        ex("Negative Pull-ups", .back, .bodyweight, reps: "5", rest: 75, cue: "Jump to the top, lower slowly (3–5 sec) — beginner builder"),

        // ── CORE LEG-RAISE FAMILY — hip-angle / leg swing, lying side-on ─
        ex("Lying Leg Raises", .core, .bodyweight, reps: "12", cue: "Flat on your back, raise straight legs, lower with control"),
        ex("Reverse Crunches", .core, .bodyweight, reps: "15", cue: "Knees to chest, curl your hips off the floor"),
        ex("Flutter Kicks", .core, .bodyweight, reps: "20", cue: "Legs low, small fast alternating kicks (20 total)"),
        ex("Scissor Kicks", .core, .bodyweight, reps: "20", cue: "Cross legs over and under, low and controlled (20 total)"),
        ex("V-Ups", .core, .bodyweight, reps: "12", cue: "Reach hands to feet, fold into a V, lower slow"),
        ex("Jackknife Sit-ups", .core, .bodyweight, reps: "12", cue: "Raise arms and legs to meet over your middle"),
        ex("Hanging Knee Raises", .core, .bodyweight, reps: "12", rest: 75, cue: "Hang from a bar, pull your knees to your chest"),

        // ── STANDING ARM-DRIVEN — wrist height, viewed facing ─────────
        ex("Jumping Jacks", .cardio, .bodyweight, reps: "30", cue: "Arms all the way overhead, feet wide and back"),
        ex("Star Jumps", .cardio, .bodyweight, reps: "15", cue: "Explode into a star — arms and legs wide — then squat in"),
        ex("Overhead Shoulder Press", .shoulders, .dumbbell, reps: "12", cue: "Press weights from shoulders to fully overhead"),
        ex("Lateral Raises", .shoulders, .dumbbell, reps: "12", cue: "Raise arms out to the sides to shoulder height, lower slow"),
        ex("Front Raises", .shoulders, .dumbbell, reps: "12", cue: "Raise the weights straight in front to shoulder height"),

        // ── TIMED HOLDS — countdown, hold the position ─────────────────
        ex("Plank", .core, .bodyweight, reps: "40 sec", timed: true, cue: "Forearms down, body in one straight line, brace your core"),
        ex("Side Plank", .core, .bodyweight, reps: "30 sec", timed: true, cue: "Stack your hips, push the bottom hip up (per side)"),
        ex("Hollow Hold", .core, .bodyweight, reps: "30 sec", timed: true, cue: "Lower back pressed down, arms and legs off the floor"),
        ex("Wall Sit", .legs, .bodyweight, reps: "45 sec", timed: true, cue: "Back flat on the wall, thighs parallel to the floor"),
        ex("Glute Bridge Hold", .legs, .bodyweight, reps: "40 sec", timed: true, cue: "Drive hips up, squeeze your glutes at the top"),
        ex("Superman Hold", .back, .bodyweight, reps: "30 sec", timed: true, cue: "Face down, lift arms, chest and legs and hold"),
        ex("Dead Hang", .back, .bodyweight, reps: "30 sec", timed: true, cue: "Hang from a bar, arms straight, shoulders engaged"),
    ]

    // MARK: - Query API (all synchronous, on-device, no AI)

    static func byMuscleGroup(_ group: MuscleGroup) -> [LibraryExercise] {
        all.filter { $0.muscleGroup == group }
    }

    static func byEquipment(_ equipment: Equipment) -> [LibraryExercise] {
        all.filter { $0.equipment == equipment }
    }

    static func search(_ text: String) -> [LibraryExercise] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.muscleGroup.displayName.localizedCaseInsensitiveContains(q)
                || $0.equipment.displayName.localizedCaseInsensitiveContains(q)
        }
    }

    /// Same-muscle alternatives for the no-AI Swap. Falls back to the whole
    /// library if the original isn't a catalog exercise (e.g. an edited name).
    static func alternatives(to exercise: WorkoutExercise) -> [LibraryExercise] {
        guard let match = all.first(where: { $0.name == exercise.name }) else {
            return all.filter { $0.name != exercise.name }
        }
        return all.filter { $0.muscleGroup == match.muscleGroup && $0.name != match.name }
    }
}
