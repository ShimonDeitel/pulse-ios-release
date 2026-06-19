import SwiftUI
import Combine

/// Draws a real-time stick-figure skeleton over the camera feed using the
/// joint positions published by `PoseDetectionService`. Color is driven by
/// `formIsGood`: green when the AI is happy with the form (rep will count),
/// red when form is off (rep won't count).
///
/// Vision coords are normalized 0…1 with y=0 at the BOTTOM. We flip y on
/// the way out so the skeleton lines up with the on-screen video.
///
/// We do NOT flip x. The PoseDetectionService already enables
/// `isVideoMirrored = true` on the data-output connection, so Vision sees
/// the same mirrored frame the user does. Flipping again here would
/// double-mirror and put the skeleton on the wrong side of the body —
/// which is exactly the bug the user reported ("when I move my right hand
/// the skeleton's left hand moves").
struct SkeletonOverlay: View {
    let joints: [PoseJoint: CGPoint]
    let formIsGood: Bool
    /// Kept as an explicit parameter for future re-tuning, but defaults to
    /// false because Vision already sees the mirrored frame.
    var mirrored: Bool = false

    /// Bone connections — pairs of joints to connect with a line.
    /// Each limb is now broken into TWO segments using the new derived
    /// midpoints (shoulder→bicep→elbow, elbow→forearm→wrist, etc.) so
    /// the skeleton has more visible articulation along each limb.
    private static let bones: [(PoseJoint, PoseJoint)] = [
        // ── torso ─────────────────────────────────────
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        // ── arms (3 segments each with bicep + forearm midpoints) ──
        (.leftShoulder, .leftBicep), (.leftBicep, .leftElbow),
        (.leftElbow, .leftForearm), (.leftForearm, .leftWrist),
        (.rightShoulder, .rightBicep), (.rightBicep, .rightElbow),
        (.rightElbow, .rightForearm), (.rightForearm, .rightWrist),
        // ── legs (3 segments each with thigh + shin midpoints) ─────
        (.leftHip, .leftThigh), (.leftThigh, .leftKnee),
        (.leftKnee, .leftShin), (.leftShin, .leftAnkle),
        (.rightHip, .rightThigh), (.rightThigh, .rightKnee),
        (.rightKnee, .rightShin), (.rightShin, .rightAnkle),
        // ── head (neck → head center → nose) ──────────
        (.neck, .head), (.head, .nose)
    ]

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let stroke = formIsGood ? PulseColors.green : PulseColors.signal
                let glow = formIsGood
                    ? PulseColors.green.opacity(0.4)
                    : PulseColors.signal.opacity(0.45)

                // Draw a soft glow stroke underneath, then the bright line.
                for (a, b) in Self.bones {
                    guard let pa = joints[a], let pb = joints[b] else { continue }
                    let p1 = mapToView(pa, in: size)
                    let p2 = mapToView(pb, in: size)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    ctx.stroke(path, with: .color(glow), lineWidth: 10)
                    ctx.stroke(path, with: .color(stroke), lineWidth: 3.5)
                }

                // Joint dots — bigger ones on the major joints the user
                // mentioned (head, wrists/hands, knees, ankles), smaller
                // ones on the derived midpoints (biceps, forearms, thighs,
                // shins).
                for (joint, p) in joints {
                    let pt = mapToView(p, in: size)
                    let r: CGFloat = joint.dotRadius
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(stroke))
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5)),
                             with: .color(.white.opacity(0.9)))
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Vision (x, y∈[0..1], y from bottom) → view coords (y from top).
    private func mapToView(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let x = mirrored ? (1 - p.x) * size.width : p.x * size.width
        let y = (1 - p.y) * size.height
        return CGPoint(x: x, y: y)
    }
}

// (ReferenceSkeletonOverlay removed — user requested no transparent ghost
// skeleton. The green/red user skeleton is now the sole guidance signal.)
