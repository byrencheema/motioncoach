import AVFoundation
import Combine
import Foundation

final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var stats = DrillStats()
    @Published private(set) var cameraStatus: CameraStatus = .unknown
    @Published private(set) var modelStatus: ModelStatus = .notLoaded

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "motioncoach.camera.session")
    private let detectionQueue = DispatchQueue(label: "motioncoach.camera.detection")
    private let detector = CoreMLYOLODetector()
    private let shotCounter = ShotCounter()
    private var onMake: (() -> Void)?

    override init() {
        super.init()
        modelStatus = detector.isModelAvailable ? .loaded : .missing
    }

    func configure(onMake: @escaping () -> Void) {
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
        stats = DrillStats()
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
            let detections = try detector.detections(in: sampleBuffer)
            let event = shotCounter.process(detections)

            let stats = shotCounter.stats
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stats = stats
                if case .make = event {
                    self.onMake?()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.modelStatus = .failed(error.localizedDescription)
            }
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
        case .notLoaded, .loaded:
            return nil
        case .missing:
            return "Add best.mlpackage to the target to enable shot detection."
        case .failed(let message):
            return "Model error: \(message)"
        }
    }
}
