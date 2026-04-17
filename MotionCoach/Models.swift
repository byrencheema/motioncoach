import Foundation
import CoreGraphics

enum DrillKind: Codable, Hashable, Identifiable {
    case freeShoot
    case makeTarget(Int)
    case timed(TimeInterval)
    case formAnalysis

    var id: String {
        switch self {
        case .freeShoot:
            return "freeShoot"
        case .makeTarget(let target):
            return "makeTarget-\(target)"
        case .timed(let duration):
            return "timed-\(Int(duration))"
        case .formAnalysis:
            return "formAnalysis"
        }
    }

    var title: String {
        switch self {
        case .freeShoot:
            return "Free Shoot"
        case .makeTarget(let target):
            return "Make \(target)"
        case .timed(let duration):
            return "\(Int(duration / 60)) Min"
        case .formAnalysis:
            return "Form Check"
        }
    }

    var summaryTitle: String {
        switch self {
        case .freeShoot:
            return "Free Shoot"
        case .makeTarget(let target):
            return "Make \(target)"
        case .timed(let duration):
            return "\(Int(duration / 60))-Minute Drill"
        case .formAnalysis:
            return "Form Analysis"
        }
    }

    var sfSymbol: String {
        switch self {
        case .freeShoot:
            return "figure.basketball"
        case .makeTarget:
            return "target"
        case .timed:
            return "timer"
        case .formAnalysis:
            return "figure.stand"
        }
    }
}

struct DrillConfiguration: Hashable {
    var kind: DrillKind = .freeShoot
}

struct DrillStats: Codable, Equatable, Hashable {
    var makes: Int = 0
    var attempts: Int = 0

    var misses: Int {
        max(0, attempts - makes)
    }

    var fieldGoalPercentage: Double {
        attempts == 0 ? 0 : (Double(makes) / Double(attempts)) * 100
    }
}

struct DrillSession: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var drillKind: DrillKind
    var stats: DrillStats
    var formStats: FormStats?

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

enum DetectorClass: Int, Codable, CaseIterable {
    case ball = 0
    case ballInBasket = 1
    case player = 2
    case basket = 3
    case playerShooting = 4

    static let classCount = 5

    var label: String {
        switch self {
        case .ball: return "Ball"
        case .ballInBasket: return "Ball in Basket"
        case .player: return "Player"
        case .basket: return "Basket"
        case .playerShooting: return "Shooting"
        }
    }
}

struct Detection: Identifiable {
    let id = UUID()
    var detectedClass: DetectorClass
    var confidence: Double
    var boundingBox: CGRect

    var center: CGPoint {
        CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }
}

enum ShotPhase: String, Codable {
    case idle
    case load
    case setPoint
    case release
    case followThrough
}

enum BodyJoint: String, Codable, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder, leftElbow, rightElbow
    case leftWrist, rightWrist, leftHip, rightHip
    case leftKnee, rightKnee, leftAnkle, rightAnkle
    case neck, root
}

struct PoseLandmark: Codable, Equatable {
    var joint: BodyJoint
    var x: CGFloat
    var y: CGFloat
    var confidence: CGFloat
}

struct FormAngles: Codable, Equatable, Hashable {
    var elbowAngle: Double?
    var kneeBend: Double?
    var releaseHeight: Double?
    var shoulderAlignment: Double?
}

struct FormRep: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    var setPointAngles: FormAngles
    var releaseAngles: FormAngles
    var wasMake: Bool
}

struct FormStats: Codable, Equatable, Hashable {
    var reps: [FormRep] = []

    var repCount: Int { reps.count }

    var avgElbowAtSet: Double? {
        average(of: \.setPointAngles.elbowAngle)
    }

    var avgElbowAtRelease: Double? {
        average(of: \.releaseAngles.elbowAngle)
    }

    var avgKneeBend: Double? {
        average(of: \.setPointAngles.kneeBend)
    }

    var elbowConsistency: Double? {
        standardDeviation(of: \.releaseAngles.elbowAngle)
    }

    var kneeConsistency: Double? {
        standardDeviation(of: \.setPointAngles.kneeBend)
    }

    var overallConsistencyScore: Double? {
        guard let eSd = elbowConsistency, let kSd = kneeConsistency else { return nil }
        let avgSd = (eSd + kSd) / 2.0
        return max(0, min(100, 100 - avgSd * 4))
    }

    private func average(of keyPath: KeyPath<FormRep, Double?>) -> Double? {
        let values = reps.compactMap { $0[keyPath: keyPath] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func standardDeviation(of keyPath: KeyPath<FormRep, Double?>) -> Double? {
        let values = reps.compactMap { $0[keyPath: keyPath] }
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
}
