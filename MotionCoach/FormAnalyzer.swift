import Foundation
import CoreGraphics

// Biomechanics angle ranges sourced from:
//   Okazaki & Rodacki (2012), "Increased distance of shooting on basketball jump shot",
//     Journal of Sports Science and Medicine.
//   Miller & Bartlett (1996), "The effects of increased shooting distance in the basketball jump shot",
//     Journal of Sports Sciences, 14(3).
//   Knudson (1993), "Biomechanics of the basketball jump shot", JOPERD 64(2).
//   Physiopedia, "Biomechanics of the Basketball Jump Shot".
// Key findings: set-point elbow ~85-100 deg, release elbow ~150-170 deg, knee flexion
// ~50-70 deg at load. Elite shooter form-angle SD across reps is typically < 5 deg.
final class FormAnalyzer {
    private let confidenceThreshold: CGFloat = 0.3
    private let setPointElbowRange = 75.0...110.0
    private let releaseElbowRange = 140.0...180.0
    private let loadKneeThreshold = 130.0
    private let hysteresisFrames = 3

    private(set) var currentPhase: ShotPhase = .idle
    private(set) var currentAngles = FormAngles()
    private(set) var currentLandmarks: [PoseLandmark] = []
    private(set) var formStats = FormStats()

    private var setPointSnapshot: FormAngles?
    private var releaseSnapshot: FormAngles?
    private var shootingArm: ShootingArm = .right
    private var armDetected = false
    private var phaseFrameCount = 0
    private var pendingPhase: ShotPhase = .idle
    private var followThroughStart: Date?

    enum ShootingArm {
        case left, right
    }

    func process(landmarks: [PoseLandmark]) {
        currentLandmarks = landmarks
        let dict = landmarkDict(landmarks)

        if !armDetected {
            detectShootingArm(dict)
        }

        currentAngles = computeAngles(dict)
        updatePhase()
    }

    func registerRep(wasMake: Bool) {
        let rep = FormRep(
            timestamp: Date(),
            setPointAngles: setPointSnapshot ?? currentAngles,
            releaseAngles: releaseSnapshot ?? currentAngles,
            wasMake: wasMake
        )
        formStats.reps.append(rep)
        setPointSnapshot = nil
        releaseSnapshot = nil
    }

    func reset() {
        currentPhase = .idle
        currentAngles = FormAngles()
        currentLandmarks = []
        formStats = FormStats()
        setPointSnapshot = nil
        releaseSnapshot = nil
        armDetected = false
        shootingArm = .right
        phaseFrameCount = 0
        pendingPhase = .idle
        followThroughStart = nil
    }

    private func landmarkDict(_ landmarks: [PoseLandmark]) -> [BodyJoint: PoseLandmark] {
        var dict: [BodyJoint: PoseLandmark] = [:]
        for lm in landmarks where lm.confidence >= confidenceThreshold {
            dict[lm.joint] = lm
        }
        return dict
    }

    private func detectShootingArm(_ dict: [BodyJoint: PoseLandmark]) {
        guard let lw = dict[.leftWrist], let rw = dict[.rightWrist],
              let ls = dict[.leftShoulder], let rs = dict[.rightShoulder] else { return }

        let leftAbove = lw.y > ls.y
        let rightAbove = rw.y > rs.y

        if leftAbove && !rightAbove {
            shootingArm = .left
            armDetected = true
        } else if rightAbove && !leftAbove {
            shootingArm = .right
            armDetected = true
        }
    }

    private func computeAngles(_ dict: [BodyJoint: PoseLandmark]) -> FormAngles {
        let (shoulder, elbow, wrist) = shootingArmJoints(dict)
        let elbowAngle = computeElbowAngle(shoulder: shoulder, elbow: elbow, wrist: wrist)
        let kneeBend = computeKneeBend(dict)
        let releaseHeight = computeReleaseHeight(wrist: wrist, nose: dict[.nose])
        let shoulderAlignment = computeShoulderAlignment(left: dict[.leftShoulder], right: dict[.rightShoulder])

        return FormAngles(
            elbowAngle: elbowAngle,
            kneeBend: kneeBend,
            releaseHeight: releaseHeight,
            shoulderAlignment: shoulderAlignment
        )
    }

    private func shootingArmJoints(_ dict: [BodyJoint: PoseLandmark]) -> (PoseLandmark?, PoseLandmark?, PoseLandmark?) {
        switch shootingArm {
        case .right:
            return (dict[.rightShoulder], dict[.rightElbow], dict[.rightWrist])
        case .left:
            return (dict[.leftShoulder], dict[.leftElbow], dict[.leftWrist])
        }
    }

    private func computeElbowAngle(shoulder: PoseLandmark?, elbow: PoseLandmark?, wrist: PoseLandmark?) -> Double? {
        guard let s = shoulder, let e = elbow, let w = wrist else { return nil }
        return angleBetween(
            a: CGPoint(x: s.x, y: s.y),
            vertex: CGPoint(x: e.x, y: e.y),
            c: CGPoint(x: w.x, y: w.y)
        )
    }

    private func computeKneeBend(_ dict: [BodyJoint: PoseLandmark]) -> Double? {
        var angles: [Double] = []
        if let lh = dict[.leftHip], let lk = dict[.leftKnee], let la = dict[.leftAnkle] {
            angles.append(angleBetween(
                a: CGPoint(x: lh.x, y: lh.y),
                vertex: CGPoint(x: lk.x, y: lk.y),
                c: CGPoint(x: la.x, y: la.y)
            ))
        }
        if let rh = dict[.rightHip], let rk = dict[.rightKnee], let ra = dict[.rightAnkle] {
            angles.append(angleBetween(
                a: CGPoint(x: rh.x, y: rh.y),
                vertex: CGPoint(x: rk.x, y: rk.y),
                c: CGPoint(x: ra.x, y: ra.y)
            ))
        }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / Double(angles.count)
    }

    private func computeReleaseHeight(wrist: PoseLandmark?, nose: PoseLandmark?) -> Double? {
        guard let w = wrist, let n = nose else { return nil }
        return Double(w.y - n.y)
    }

    private func computeShoulderAlignment(left: PoseLandmark?, right: PoseLandmark?) -> Double? {
        guard let l = left, let r = right else { return nil }
        let dx = Double(r.x - l.x)
        let dy = Double(r.y - l.y)
        return atan2(dy, dx) * 180.0 / .pi
    }

    private func updatePhase() {
        let nextPhase = computeNextPhase()

        if nextPhase == pendingPhase {
            phaseFrameCount += 1
        } else {
            pendingPhase = nextPhase
            phaseFrameCount = 1
        }

        if phaseFrameCount >= hysteresisFrames && pendingPhase != currentPhase {
            transitionTo(pendingPhase)
        }

        if currentPhase == .followThrough, let start = followThroughStart,
           Date().timeIntervalSince(start) > 0.5 {
            currentPhase = .idle
            followThroughStart = nil
        }
    }

    private func computeNextPhase() -> ShotPhase {
        let elbow = currentAngles.elbowAngle
        let knee = currentAngles.kneeBend

        switch currentPhase {
        case .idle:
            if let k = knee, k < loadKneeThreshold {
                return .load
            }
        case .load:
            if let e = elbow, setPointElbowRange.contains(e) {
                return .setPoint
            }
        case .setPoint:
            if let e = elbow, e > setPointElbowRange.upperBound {
                return .release
            }
        case .release:
            if let e = elbow, releaseElbowRange.contains(e) {
                return .followThrough
            }
        case .followThrough:
            return .followThrough
        }

        return currentPhase
    }

    private func transitionTo(_ phase: ShotPhase) {
        currentPhase = phase
        switch phase {
        case .setPoint:
            setPointSnapshot = currentAngles
        case .release:
            releaseSnapshot = currentAngles
        case .followThrough:
            followThroughStart = Date()
        default:
            break
        }
    }

    private func angleBetween(a: CGPoint, vertex: CGPoint, c: CGPoint) -> Double {
        let v1 = CGPoint(x: a.x - vertex.x, y: a.y - vertex.y)
        let v2 = CGPoint(x: c.x - vertex.x, y: c.y - vertex.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let cross = v1.x * v2.y - v1.y * v2.x
        return abs(atan2(cross, dot) * 180.0 / .pi)
    }
}
