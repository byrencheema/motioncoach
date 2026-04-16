import AVFoundation
import CoreML
import CoreVideo
import Foundation
import Vision

final class ShotCounter {
    private let shotCooldown: TimeInterval = 1.5
    private let makeCooldown: TimeInterval = 2.0
    private let ballConfidence: Double = 0.50
    private let basketConfidence: Double = 0.50
    private let ballInBasketConfidence: Double = 0.45

    private(set) var stats = DrillStats()
    private var lastShotTime = Date.distantPast
    private var lastMakeTime = Date.distantPast

    private var previousBallCenter: CGPoint?
    private var lastKnownBasketRect: CGRect?
    private var ballWasAboveBasket = false

    func process(_ detections: [Detection], at timestamp: Date = Date()) -> ShotEvent? {
        var currentBall: Detection?
        var currentBasket: Detection?
        var hasBallInBasket = false

        for detection in detections {
            switch detection.detectedClass {
            case .ball where detection.confidence >= ballConfidence:
                if currentBall == nil || detection.confidence > currentBall!.confidence {
                    currentBall = detection
                }
            case .basket where detection.confidence >= basketConfidence:
                if currentBasket == nil || detection.confidence > currentBasket!.confidence {
                    currentBasket = detection
                }
            case .ballInBasket where detection.confidence >= ballInBasketConfidence:
                hasBallInBasket = true
            case .playerShooting:
                break
            default:
                break
            }
        }

        if let basket = currentBasket {
            lastKnownBasketRect = basket.boundingBox
        }

        var event: ShotEvent?

        if hasBallInBasket {
            if registerMake(at: timestamp) {
                let center = lastKnownBasketRect.map {
                    CGPoint(x: $0.midX, y: $0.midY)
                } ?? .zero
                event = .make(center: center)
            }
        }

        guard let ball = currentBall, let basketRect = lastKnownBasketRect else {
            previousBallCenter = currentBall?.center
            return event
        }

        let ballCenter = ball.center
        let ballAboveBasket = ballCenter.y > basketRect.maxY
        let ballInBasketZone = basketRect.insetBy(dx: -basketRect.width * 0.15, dy: -basketRect.height * 0.3)
            .contains(ballCenter)

        if event == nil && ballWasAboveBasket && !ballAboveBasket && ballInBasketZone {
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
    private static let inputSize = 640
    private static let boxCount = 8400
    private static let confThreshold: Float = 0.40
    private static let iouThreshold: Float = 0.45

    private let model: MLModel?
    private let visionModel: VNCoreMLModel?

    init() {
        let (m, v) = Self.loadModel()
        self.model = m
        self.visionModel = v
    }

    var isModelAvailable: Bool {
        model != nil
    }

    func detections(in sampleBuffer: CMSampleBuffer) throws -> [Detection] {
        if let visionModel {
            return try visionDetections(in: sampleBuffer, model: visionModel)
        }
        guard let model, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return []
        }
        return try rawDetections(in: pixelBuffer, model: model)
    }

    private func visionDetections(in sampleBuffer: CMSampleBuffer, model: VNCoreMLModel) throws -> [Detection] {
        let request = VNCoreMLRequest(model: model)
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

    private func rawDetections(in pixelBuffer: CVPixelBuffer, model: MLModel) throws -> [Detection] {
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try model.prediction(from: input)

        guard let multiArray = output.featureValue(for: "cat_22")?.multiArrayValue else {
            return []
        }

        let ptr = UnsafeBufferPointer(
            start: multiArray.dataPointer.assumingMemoryBound(to: Float16.self),
            count: multiArray.count
        )

        let rows = 9
        let cols = Self.boxCount
        var candidates: [Detection] = []

        for j in 0..<cols {
            let cx = Float(ptr[0 * cols + j])
            let cy = Float(ptr[1 * cols + j])
            let w  = Float(ptr[2 * cols + j])
            let h  = Float(ptr[3 * cols + j])

            var bestClassIdx = 0
            var bestScore: Float = -Float.infinity
            for c in 0..<DetectorClass.classCount {
                let score = Float(ptr[(4 + c) * cols + j])
                if score > bestScore {
                    bestScore = score
                    bestClassIdx = c
                }
            }

            guard bestScore >= Self.confThreshold,
                  let detectedClass = DetectorClass(rawValue: bestClassIdx) else {
                continue
            }

            let inputSize = Float(Self.inputSize)
            let normX = (cx - w / 2) / inputSize
            let normY = (cy - h / 2) / inputSize
            let normW = w / inputSize
            let normH = h / inputSize

            let box = CGRect(
                x: CGFloat(normX),
                y: CGFloat(normY),
                width: CGFloat(normW),
                height: CGFloat(normH)
            )

            candidates.append(Detection(
                detectedClass: detectedClass,
                confidence: Double(bestScore),
                boundingBox: box
            ))
        }

        return Self.nms(candidates, iouThreshold: Self.iouThreshold)
    }

    private static func nms(_ detections: [Detection], iouThreshold: Float) -> [Detection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [Detection] = []

        for candidate in sorted {
            let dominated = kept.contains { existing in
                existing.detectedClass == candidate.detectedClass
                && iou(existing.boundingBox, candidate.boundingBox) > iouThreshold
            }
            if !dominated {
                kept.append(candidate)
            }
        }

        return kept
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let interArea = Float(intersection.width * intersection.height)
        let unionArea = Float(a.width * a.height + b.width * b.height) - interArea
        return unionArea > 0 ? interArea / unionArea : 0
    }

    private static func loadModel() -> (MLModel?, VNCoreMLModel?) {
        let candidateURLs = [
            Bundle.main.url(forResource: "best", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "best", withExtension: "mlpackage")
        ]

        guard let modelURL = candidateURLs.compactMap({ $0 }).first,
              let model = try? MLModel(contentsOf: modelURL) else {
            return (nil, nil)
        }

        let visionModel = try? VNCoreMLModel(for: model)
        return (model, visionModel)
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
        case "1", "ball in basket", "ballinbasket":
            self = .ballInBasket
        case "2", "player":
            self = .player
        case "3", "basket", "rim", "hoop", "basketball hoop":
            self = .basket
        case "4", "player shooting", "playershooting", "shooting":
            self = .playerShooting
        default:
            return nil
        }
    }
}
