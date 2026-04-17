import AVFoundation
import Vision
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

let videoPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSString(string: "~/Downloads/139533-772542665.mp4").expandingTildeInPath

let url = URL(fileURLWithPath: videoPath)
let outputURL = URL(fileURLWithPath: videoPath.replacingOccurrences(of: ".mp4", with: "_skeleton.mp4"))

guard FileManager.default.fileExists(atPath: videoPath) else {
    print("Video not found: \(videoPath)")
    exit(1)
}

try? FileManager.default.removeItem(at: outputURL)

let asset = AVAsset(url: url)
guard let videoTrack = asset.tracks(withMediaType: .video).first else {
    print("No video track")
    exit(1)
}

let naturalSize = videoTrack.naturalSize
let transform = videoTrack.preferredTransform
let fps = videoTrack.nominalFrameRate
let duration = CMTimeGetSeconds(asset.duration)

var renderWidth = Int(naturalSize.width)
var renderHeight = Int(naturalSize.height)
let isRotated = abs(transform.b) == 1.0 && abs(transform.c) == 1.0
if isRotated {
    renderWidth = Int(naturalSize.height)
    renderHeight = Int(naturalSize.width)
}

print("=== Skeleton Renderer ===")
print("Input: \(url.lastPathComponent)")
print("Output: \(outputURL.lastPathComponent)")
print("Size: \(renderWidth)x\(renderHeight) | FPS: \(Int(fps)) | Duration: \(String(format: "%.1f", duration))s")

let reader = try! AVAssetReader(asset: asset)
let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
readerOutput.alwaysCopiesSampleData = false
reader.add(readerOutput)

let writer = try! AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: renderWidth,
    AVVideoHeightKey: renderHeight,
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: writerInput,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: renderWidth,
        kCVPixelBufferHeightKey as String: renderHeight,
    ]
)
writer.add(writerInput)

reader.startReading()
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let bones: [(String, String)] = [
    ("leftShoulder", "rightShoulder"),
    ("leftShoulder", "leftHip"),
    ("rightShoulder", "rightHip"),
    ("leftHip", "rightHip"),
    ("leftShoulder", "leftElbow"),
    ("leftElbow", "leftWrist"),
    ("rightShoulder", "rightElbow"),
    ("rightElbow", "rightWrist"),
    ("leftHip", "leftKnee"),
    ("leftKnee", "leftAnkle"),
    ("rightHip", "rightKnee"),
    ("rightKnee", "rightAnkle"),
    ("neck", "leftShoulder"),
    ("neck", "rightShoulder"),
]

let jointNames: [VNHumanBodyPoseObservation.JointName] = [
    .nose, .leftEye, .rightEye, .leftEar, .rightEar,
    .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
    .leftWrist, .rightWrist, .leftHip, .rightHip,
    .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    .neck, .root
]

func jointKey(_ j: VNHumanBodyPoseObservation.JointName) -> String {
    switch j {
    case .nose: return "nose"
    case .leftEye: return "leftEye"
    case .rightEye: return "rightEye"
    case .leftEar: return "leftEar"
    case .rightEar: return "rightEar"
    case .leftShoulder: return "leftShoulder"
    case .rightShoulder: return "rightShoulder"
    case .leftElbow: return "leftElbow"
    case .rightElbow: return "rightElbow"
    case .leftWrist: return "leftWrist"
    case .rightWrist: return "rightWrist"
    case .leftHip: return "leftHip"
    case .rightHip: return "rightHip"
    case .leftKnee: return "leftKnee"
    case .rightKnee: return "rightKnee"
    case .leftAnkle: return "leftAnkle"
    case .rightAnkle: return "rightAnkle"
    case .neck: return "neck"
    case .root: return "root"
    default: return "unknown"
    }
}

func angleBetween(a: CGPoint, vertex: CGPoint, c: CGPoint) -> Double {
    let v1 = CGPoint(x: a.x - vertex.x, y: a.y - vertex.y)
    let v2 = CGPoint(x: c.x - vertex.x, y: c.y - vertex.y)
    let dot = v1.x * v2.x + v1.y * v2.y
    let cross = v1.x * v2.y - v1.y * v2.x
    return abs(atan2(cross, dot) * 180.0 / .pi)
}

let tealR: CGFloat = 58.0/255; let tealG: CGFloat = 191.0/255; let tealB: CGFloat = 173.0/255
let orangeR: CGFloat = 255.0/255; let orangeG: CGFloat = 149.0/255; let orangeB: CGFloat = 0.0/255
let greenR: CGFloat = 52.0/255; let greenG: CGFloat = 199.0/255; let greenB: CGFloat = 89.0/255

let shootingJoints: Set<String> = ["rightElbow", "rightWrist", "rightShoulder"]
let kneeJoints: Set<String> = ["leftKnee", "rightKnee"]

var frameIndex = 0
let totalFrames = Int(duration * Double(fps))

while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
    frameIndex += 1

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

    let poseRequest = VNDetectHumanBodyPoseRequest()
    let orientation: CGImagePropertyOrientation = isRotated ? .right : .up
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
    try? handler.perform([poseRequest])

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pbWidth = CVPixelBufferGetWidth(pixelBuffer)
    let pbHeight = CVPixelBufferGetHeight(pixelBuffer)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: baseAddress,
        width: pbWidth,
        height: pbHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        continue
    }

    if let observation = poseRequest.results?.first {
        var points: [String: CGPoint] = [:]
        for jn in jointNames {
            guard let p = try? observation.recognizedPoint(jn), p.confidence > 0.3 else { continue }
            let key = jointKey(jn)
            let screenX = p.location.x * CGFloat(pbWidth)
            let screenY = p.location.y * CGFloat(pbHeight)
            points[key] = CGPoint(x: screenX, y: screenY)
        }

        var rElbow: Double? = nil
        if let s = points["rightShoulder"], let e = points["rightElbow"], let w = points["rightWrist"] {
            rElbow = angleBetween(a: s, vertex: e, c: w)
        }
        var lElbow: Double? = nil
        if let s = points["leftShoulder"], let e = points["leftElbow"], let w = points["leftWrist"] {
            lElbow = angleBetween(a: s, vertex: e, c: w)
        }
        var rKnee: Double? = nil
        if let h = points["rightHip"], let k = points["rightKnee"], let a = points["rightAnkle"] {
            rKnee = angleBetween(a: h, vertex: k, c: a)
        }
        var lKnee: Double? = nil
        if let h = points["leftHip"], let k = points["leftKnee"], let a = points["leftAnkle"] {
            lKnee = angleBetween(a: h, vertex: k, c: a)
        }

        let elbowAngle: Double? = rElbow ?? lElbow

        var phase = "idle"
        if let e = elbowAngle {
            if e > 150 { phase = "follow through" }
            else if e > 110 { phase = "release" }
            else if e >= 75 { phase = "set point" }
        }

        func elbowColor(_ angle: Double?) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            guard let a = angle else { return (1, 1, 1) }
            let idealSet = 85.0...105.0
            let idealRelease = 145.0...175.0
            let inIdeal = idealSet.contains(a) || idealRelease.contains(a)
            let close = (75.0...115.0).contains(a) || (135.0...180.0).contains(a)
            if inIdeal { return (greenR, greenG, greenB) }
            if close { return (orangeR, orangeG, orangeB) }
            return (1, 0.3, 0.3)
        }

        func kneeColor(_ angle: Double?) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            guard let a = angle else { return (1, 1, 1) }
            if (50.0...80.0).contains(a) { return (greenR, greenG, greenB) }
            if (40.0...100.0).contains(a) { return (orangeR, orangeG, orangeB) }
            return (1, 1, 1)
        }

        let rElbowColor = elbowColor(rElbow)
        let lElbowColor = elbowColor(lElbow)
        let rKneeColor = kneeColor(rKnee)
        let lKneeColor = kneeColor(lKnee)

        let neutralColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (1, 1, 1)
        let torsoColor: (r: CGFloat, g: CGFloat, b: CGFloat) = (1, 1, 1)

        func colorForBone(_ bone: (String, String)) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            let rightArmBones: Set<String> = ["rightShoulder-rightElbow", "rightElbow-rightWrist"]
            let leftArmBones: Set<String> = ["leftShoulder-leftElbow", "leftElbow-leftWrist"]
            let rightLegBones: Set<String> = ["rightHip-rightKnee", "rightKnee-rightAnkle"]
            let leftLegBones: Set<String> = ["leftHip-leftKnee", "leftKnee-leftAnkle"]
            let key = "\(bone.0)-\(bone.1)"
            if rightArmBones.contains(key) {
                return (rElbowColor.r, rElbowColor.g, rElbowColor.b, 1.0)
            }
            if leftArmBones.contains(key) {
                return (lElbowColor.r, lElbowColor.g, lElbowColor.b, 1.0)
            }
            if rightLegBones.contains(key) {
                return (rKneeColor.r, rKneeColor.g, rKneeColor.b, 1.0)
            }
            if leftLegBones.contains(key) {
                return (lKneeColor.r, lKneeColor.g, lKneeColor.b, 1.0)
            }
            return (torsoColor.r, torsoColor.g, torsoColor.b, 0.9)
        }

        ctx.setLineCap(.round)
        ctx.setLineWidth(6.0)

        for bone in bones {
            guard let a = points[bone.0], let b = points[bone.1] else { continue }
            let c = colorForBone(bone)
            ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            ctx.beginPath()
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }

        let jointRadius: CGFloat = 8.0
        for (key, pt) in points {
            var color = neutralColor
            switch key {
            case "rightElbow", "rightWrist", "rightShoulder": color = rElbowColor
            case "leftElbow", "leftWrist", "leftShoulder": color = lElbowColor
            case "rightKnee", "rightAnkle", "rightHip": color = rKneeColor
            case "leftKnee", "leftAnkle", "leftHip": color = lKneeColor
            default: break
            }
            ctx.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1.0)
            ctx.fillEllipse(in: CGRect(
                x: pt.x - jointRadius, y: pt.y - jointRadius,
                width: jointRadius * 2, height: jointRadius * 2
            ))
        }

        _ = elbowAngle
        _ = phase
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    while !writerInput.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.01)
    }
    adaptor.append(pixelBuffer, withPresentationTime: timestamp)

    if frameIndex % 30 == 0 {
        let pct = Int(Double(frameIndex) / Double(totalFrames) * 100)
        print("Processing: \(pct)% (\(frameIndex)/\(totalFrames) frames)")
    }
}

writerInput.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
reader.cancelReading()

print("")
print("Done! Saved to: \(outputURL.path)")
let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("Size: \(fileSize / 1024 / 1024)MB")
