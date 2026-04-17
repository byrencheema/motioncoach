import AVFoundation
import Combine
import Foundation
import Vision

struct DebugInfo: Equatable {
    var detectionCount: Int = 0
    var ballDetected: Bool = false
    var basketDetected: Bool = false
    var ballInBasketDetected: Bool = false
    var ballConfidence: Double = 0
    var basketConfidence: Double = 0
    var ballInBasketConfidence: Double = 0
    var ballCenter: CGPoint = .zero
    var basketCenter: CGPoint = .zero
    var framesProcessed: Int = 0
    var lastError: String?
}

final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var stats = DrillStats()
    @Published private(set) var cameraStatus: CameraStatus = .unknown
    @Published private(set) var modelStatus: ModelStatus = .notLoaded
    @Published private(set) var debugInfo = DebugInfo()
    @Published private(set) var detections: [Detection] = []
    @Published private(set) var currentLandmarks: [PoseLandmark] = []
    @Published private(set) var currentPhase: ShotPhase = .idle
    @Published private(set) var currentAngles = FormAngles()
    @Published private(set) var formStats = FormStats()

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "motioncoach.camera.session")
    private let detectionQueue = DispatchQueue(label: "motioncoach.camera.detection")
    private let detector = CoreMLYOLODetector()
    private let shotCounter = ShotCounter()
    private let formAnalyzer = FormAnalyzer()
    private var onMake: (() -> Void)?
    private var formModeEnabled = false
    private var frameCount = 0

    override init() {
        super.init()
        modelStatus = detector.isModelAvailable ? .loaded : .missing
    }

    func configure(formMode: Bool = false, onMake: @escaping () -> Void) {
        self.formModeEnabled = formMode
        self.onMake = onMake
        checkPermissionAndStart()
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func resetStats() {
        shotCounter.reset()
        formAnalyzer.reset()
        stats = DrillStats()
        formStats = FormStats()
        currentLandmarks = []
        currentPhase = .idle
        currentAngles = FormAngles()
        frameCount = 0
        debugInfo = DebugInfo()
    }

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .authorized
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraStatus = granted ? .authorized : .denied
                    if granted {
                        self?.startSession()
                    }
                }
            }
        case .denied, .restricted:
            cameraStatus = .denied
        @unknown default:
            cameraStatus = .denied
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        defer {
            session.commitConfiguration()
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            DispatchQueue.main.async { [weak self] in
                self?.cameraStatus = .unavailable
            }
            return
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: detectionQueue)

        guard session.canAddOutput(output) else {
            DispatchQueue.main.async { [weak self] in
                self?.cameraStatus = .unavailable
            }
            return
        }

        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        do {
            let frameDetections = try detector.detections(in: sampleBuffer)
            let event = shotCounter.process(frameDetections)
            let stats = shotCounter.stats
            let count = frameDetections.count

            let ball = frameDetections.first(where: { $0.detectedClass == .ball })
            let basket = frameDetections.first(where: { $0.detectedClass == .basket })
            let ballInBasket = frameDetections.first(where: { $0.detectedClass == .ballInBasket })

            var landmarks: [PoseLandmark] = []
            var phase: ShotPhase = .idle
            var angles = FormAngles()
            var form = FormStats()

            if formModeEnabled {
                let poseRequest = VNDetectHumanBodyPoseRequest()
                let poseHandler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right)
                try poseHandler.perform([poseRequest])

                if let observation = poseRequest.results?.first {
                    let extracted = Self.extractLandmarks(from: observation)
                    formAnalyzer.process(landmarks: extracted)
                }

                if let event {
                    if case .make = event {
                        formAnalyzer.registerRep(wasMake: true)
                    } else {
                        formAnalyzer.registerRep(wasMake: false)
                    }
                }

                landmarks = formAnalyzer.currentLandmarks
                phase = formAnalyzer.currentPhase
                angles = formAnalyzer.currentAngles
                form = formAnalyzer.formStats
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stats = stats
                self.detections = frameDetections
                self.frameCount += 1
                self.debugInfo = DebugInfo(
                    detectionCount: count,
                    ballDetected: ball != nil,
                    basketDetected: basket != nil,
                    ballInBasketDetected: ballInBasket != nil,
                    ballConfidence: ball?.confidence ?? 0,
                    basketConfidence: basket?.confidence ?? 0,
                    ballInBasketConfidence: ballInBasket?.confidence ?? 0,
                    ballCenter: ball?.center ?? .zero,
                    basketCenter: basket?.center ?? .zero,
                    framesProcessed: self.frameCount,
                    lastError: nil
                )
                if self.formModeEnabled {
                    self.currentLandmarks = landmarks
                    self.currentPhase = phase
                    self.currentAngles = angles
                    self.formStats = form
                }
                if case .make = event {
                    self.onMake?()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.debugInfo.lastError = error.localizedDescription
                self.modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    private static let jointMapping: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye),
        (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        (.neck, .neck), (.root, .root)
    ]

    nonisolated private static func extractLandmarks(from observation: VNHumanBodyPoseObservation) -> [PoseLandmark] {
        jointMapping.compactMap { visionJoint, bodyJoint in
            guard let point = try? observation.recognizedPoint(visionJoint),
                  point.confidence > 0.1 else { return nil }
            return PoseLandmark(
                joint: bodyJoint,
                x: point.location.x,
                y: point.location.y,
                confidence: CGFloat(point.confidence)
            )
        }
    }
}

enum CameraStatus: Equatable {
    case unknown
    case authorized
    case denied
    case unavailable
}

enum ModelStatus: Equatable {
    case notLoaded
    case loaded
    case missing
    case failed(String)

    var message: String? {
        switch self {
        case .notLoaded:
            return "Model not loaded."
        case .loaded:
            return nil
        case .missing:
            return "Model missing — add best.mlpackage to the target."
        case .failed(let message):
            return "Model error: \(message)"
        }
    }
}
