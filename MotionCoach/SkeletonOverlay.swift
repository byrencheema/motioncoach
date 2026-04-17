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

    private static let rightArmBones: Set<String> = [
        "rightShoulder-rightElbow", "rightElbow-rightWrist"
    ]
    private static let leftArmBones: Set<String> = [
        "leftShoulder-leftElbow", "leftElbow-leftWrist"
    ]
    private static let rightLegBones: Set<String> = [
        "rightHip-rightKnee", "rightKnee-rightAnkle"
    ]
    private static let leftLegBones: Set<String> = [
        "leftHip-leftKnee", "leftKnee-leftAnkle"
    ]

    var body: some View {
        Canvas { context, size in
            let dict = landmarkDict()
            let rElbow = angle(at: .rightElbow, from: .rightShoulder, to: .rightWrist, in: dict)
            let lElbow = angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist, in: dict)
            let rKnee = angle(at: .rightKnee, from: .rightHip, to: .rightAnkle, in: dict)
            let lKnee = angle(at: .leftKnee, from: .leftHip, to: .leftAnkle, in: dict)

            let rElbowColor = elbowColor(rElbow)
            let lElbowColor = elbowColor(lElbow)
            let rKneeColor = kneeColor(rKnee)
            let lKneeColor = kneeColor(lKnee)

            for (from, to) in Self.bones {
                guard let a = dict[from], let b = dict[to] else { continue }
                let ptA = visionToScreen(a, in: size)
                let ptB = visionToScreen(b, in: size)
                var path = Path()
                path.move(to: ptA)
                path.addLine(to: ptB)
                let key = "\(from.rawValue)-\(to.rawValue)"
                let color = boneColor(for: key, rElbow: rElbowColor, lElbow: lElbowColor, rKnee: rKneeColor, lKnee: lKneeColor)
                context.stroke(path, with: .color(color), lineWidth: 3)
            }

            for landmark in landmarks where landmark.confidence >= 0.3 {
                let pt = visionToScreen(landmark, in: size)
                let r: CGFloat = 6
                let circle = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                let color = jointColor(for: landmark.joint, rElbow: rElbowColor, lElbow: lElbowColor, rKnee: rKneeColor, lKnee: lKneeColor)
                context.fill(circle, with: .color(color))
            }
        }
    }

    private func boneColor(for key: String, rElbow: Color, lElbow: Color, rKnee: Color, lKnee: Color) -> Color {
        if Self.rightArmBones.contains(key) { return rElbow }
        if Self.leftArmBones.contains(key) { return lElbow }
        if Self.rightLegBones.contains(key) { return rKnee }
        if Self.leftLegBones.contains(key) { return lKnee }
        return .white.opacity(0.8)
    }

    private func jointColor(for joint: BodyJoint, rElbow: Color, lElbow: Color, rKnee: Color, lKnee: Color) -> Color {
        switch joint {
        case .rightShoulder, .rightElbow, .rightWrist: return rElbow
        case .leftShoulder, .leftElbow, .leftWrist: return lElbow
        case .rightHip, .rightKnee, .rightAnkle: return rKnee
        case .leftHip, .leftKnee, .leftAnkle: return lKnee
        default: return .white
        }
    }

    private func elbowColor(_ angle: Double?) -> Color {
        guard let a = angle else { return .white.opacity(0.6) }
        if (85.0...105.0).contains(a) || (145.0...175.0).contains(a) { return Court.green }
        if (75.0...115.0).contains(a) || (135.0...180.0).contains(a) { return Court.orange }
        return Court.red
    }

    private func kneeColor(_ angle: Double?) -> Color {
        guard let a = angle else { return .white.opacity(0.6) }
        if (50.0...80.0).contains(a) { return Court.green }
        if (40.0...100.0).contains(a) { return Court.orange }
        return .white.opacity(0.6)
    }

    private func angle(at vertex: BodyJoint, from a: BodyJoint, to c: BodyJoint, in dict: [BodyJoint: PoseLandmark]) -> Double? {
        guard let v = dict[vertex], let pa = dict[a], let pc = dict[c] else { return nil }
        let v1 = CGPoint(x: pa.x - v.x, y: pa.y - v.y)
        let v2 = CGPoint(x: pc.x - v.x, y: pc.y - v.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let cross = v1.x * v2.y - v1.y * v2.x
        return abs(atan2(cross, dot) * 180.0 / .pi)
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
