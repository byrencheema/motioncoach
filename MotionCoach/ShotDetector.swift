import AVFoundation
import CoreML
import Foundation
import Vision

final class ShotCounter {
    private let shotCooldown: TimeInterval = 1.5
    private let makeCooldown: TimeInterval = 2.0
    private let ballConfidence: Double = 0.50
    private let basketConfidence: Double = 0.50

    private(set) var stats = DrillStats()
    private var lastShotTime = Date.distantPast
    private var lastMakeTime = Date.distantPast

    private var previousBallCenter: CGPoint?
    private var lastKnownBasketRect: CGRect?
    private var ballWasAboveBasket = false

    func process(_ detections: [Detection], at timestamp: Date = Date()) -> ShotEvent? {
        var currentBall: Detection?
        var currentBasket: Detection?

        for detection in detections {
            switch detection.detectedClass {
            case .ball where detection.confidence >= ballConfidence:
                currentBall = detection
            case .basket where detection.confidence >= basketConfidence:
                currentBasket = detection
            default:
                break
            }
        }

        if let basket = currentBasket {
            lastKnownBasketRect = basket.boundingBox
        }

        guard let ball = currentBall, let basketRect = lastKnownBasketRect else {
            previousBallCenter = currentBall?.center
            return nil
        }

        let ballCenter = ball.center
        let ballAboveBasket = ballCenter.y > basketRect.maxY
        let ballInBasketZone = basketRect.insetBy(dx: -basketRect.width * 0.15, dy: -basketRect.height * 0.3)
            .contains(ballCenter)

        var event: ShotEvent?

        if ballWasAboveBasket && !ballAboveBasket && ballInBasketZone {
            if registerMake(at: timestamp) {
                event = .make(center: CGPoint(x: basketRect.midX, y: basketRect.midY))
            }
        }

        if let prev = previousBallCenter {
            let dy = prev.y - ballCenter.y
            if dy > 0.05 && ballAboveBasket {
                if registerShot(at: timestamp) {
                    event = event ?? .attempt
                }
            }
        }

        ballWasAboveBasket = ballAboveBasket
        previousBallCenter = ballCenter
        return event
    }

    func reset() {
        stats = DrillStats()
        lastShotTime = .distantPast
        lastMakeTime = .distantPast
        previousBallCenter = nil
        lastKnownBasketRect = nil
        ballWasAboveBasket = false
    }

    private func registerShot(at timestamp: Date) -> Bool {
        guard timestamp.timeIntervalSince(lastShotTime) >= shotCooldown else {
            return false
        }

        stats.attempts += 1
        lastShotTime = timestamp
        return true
    }

    private func registerMake(at timestamp: Date) -> Bool {
        guard timestamp.timeIntervalSince(lastMakeTime) >= makeCooldown else {
            return false
        }

        if timestamp.timeIntervalSince(lastShotTime) > shotCooldown * 2 {
            stats.attempts += 1
            lastShotTime = timestamp
        }

        stats.makes += 1
        lastMakeTime = timestamp
        return true
    }
}

enum ShotEvent: Equatable {
    case attempt
    case make(center: CGPoint)
}

protocol FrameDetector {
    func detections(in sampleBuffer: CMSampleBuffer) throws -> [Detection]
}

final class CoreMLYOLODetector: FrameDetector {
    private let visionModel: VNCoreMLModel?

    init() {
        self.visionModel = Self.loadModel()
    }

    var isModelAvailable: Bool {
        visionModel != nil
    }

    func detections(in sampleBuffer: CMSampleBuffer) throws -> [Detection] {
        guard let visionModel else {
            return []
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right)
        try handler.perform([request])

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return observations.compactMap { observation in
            guard let label = observation.labels.first,
                  let detectedClass = DetectorClass(labelIdentifier: label.identifier) else {
                return nil
            }

            return Detection(
                detectedClass: detectedClass,
                confidence: Double(label.confidence),
                boundingBox: observation.boundingBox
            )
        }
    }

    private static func loadModel() -> VNCoreMLModel? {
        let candidateURLs = [
            Bundle.main.url(forResource: "best", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "best", withExtension: "mlpackage")
        ]

        guard let modelURL = candidateURLs.compactMap({ $0 }).first,
              let model = try? MLModel(contentsOf: modelURL),
              let visionModel = try? VNCoreMLModel(for: model) else {
            return nil
        }

        return visionModel
    }
}

private extension DetectorClass {
    init?(labelIdentifier: String) {
        let normalized = labelIdentifier
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "0", "ball", "basketball":
            self = .ball
        case "1", "basket", "rim", "hoop", "basketball hoop":
            self = .basket
        default:
            return nil
        }
    }
}
