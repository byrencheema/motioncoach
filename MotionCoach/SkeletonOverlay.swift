import SwiftUI

struct SkeletonOverlay: View {
    let landmarks: [PoseLandmark]
    let phase: ShotPhase

    private static let bones: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.nose, .neck),
        (.neck, .leftShoulder),
        (.neck, .rightShoulder),
    ]

    private static let shootingJoints: Set<BodyJoint> = [
        .rightElbow, .rightWrist, .rightShoulder
    ]

    private static let kneeJoints: Set<BodyJoint> = [
        .leftKnee, .rightKnee
    ]

    var body: some View {
        Canvas { context, size in
            let dict = landmarkDict()

            for (from, to) in Self.bones {
                guard let a = dict[from], let b = dict[to] else { continue }
                let ptA = visionToScreen(a, in: size)
                let ptB = visionToScreen(b, in: size)
                var path = Path()
                path.move(to: ptA)
                path.addLine(to: ptB)
                context.stroke(path, with: .color(boneColor), lineWidth: 3)
            }

            for landmark in landmarks where landmark.confidence >= 0.3 {
                let pt = visionToScreen(landmark, in: size)
                let r: CGFloat = 6
                let circle = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                context.fill(circle, with: .color(jointColor(for: landmark.joint)))
            }
        }
    }

    private var boneColor: Color {
        switch phase {
        case .idle: return .white.opacity(0.6)
        case .load: return Court.orange
        case .setPoint: return Court.teal
        case .release, .followThrough: return Court.green
        }
    }

    private func jointColor(for joint: BodyJoint) -> Color {
        if Self.shootingJoints.contains(joint) { return Court.teal }
        if Self.kneeJoints.contains(joint) { return Court.orange }
        return .white
    }

    private func landmarkDict() -> [BodyJoint: PoseLandmark] {
        Dictionary(landmarks.map { ($0.joint, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func visionToScreen(_ landmark: PoseLandmark, in size: CGSize) -> CGPoint {
        CGPoint(
            x: landmark.x * size.width,
            y: (1 - landmark.y) * size.height
        )
    }
}
