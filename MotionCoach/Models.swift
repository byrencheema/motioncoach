import Foundation
import CoreGraphics

enum DrillKind: Codable, Hashable, Identifiable {
    case freeShoot
    case makeTarget(Int)
    case timed(TimeInterval)

    var id: String {
        switch self {
        case .freeShoot:
            return "freeShoot"
        case .makeTarget(let target):
            return "makeTarget-\(target)"
        case .timed(let duration):
            return "timed-\(Int(duration))"
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

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

enum DetectorClass: Int, Codable {
    case ball = 0
    case basket = 1
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
