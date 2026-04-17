import Vision
import AVFoundation
import CoreGraphics
import Foundation

func angleBetween(a: CGPoint, vertex: CGPoint, c: CGPoint) -> Double {
    let v1 = CGPoint(x: a.x - vertex.x, y: a.y - vertex.y)
    let v2 = CGPoint(x: c.x - vertex.x, y: c.y - vertex.y)
    let dot = v1.x * v2.x + v1.y * v2.y
    let cross = v1.x * v2.y - v1.y * v2.x
    return abs(atan2(cross, dot) * 180.0 / .pi)
}

struct FrameAngles {
    var time: Double
    var phase: String
    var rightElbow: Double?
    var leftElbow: Double?
    var rightKnee: Double?
    var leftKnee: Double?
    var releaseHeight: Double?
    var shoulderAlignment: Double?
}

let videoPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSString(string: "~/Downloads/139533-772542665.mp4").expandingTildeInPath

let url = URL(fileURLWithPath: videoPath)
guard FileManager.default.fileExists(atPath: videoPath) else {
    print("Video not found: \(videoPath)")
    exit(1)
}

let asset = AVAsset(url: url)
guard let track = asset.tracks(withMediaType: .video).first else {
    print("No video track found")
    exit(1)
}

let duration = CMTimeGetSeconds(asset.duration)
let fps = track.nominalFrameRate
let size = track.naturalSize
print("=== MotionCoach Pose Analysis ===")
print("Video: \(url.lastPathComponent)")
print("Duration: \(String(format: "%.1f", duration))s | FPS: \(Int(fps)) | Resolution: \(Int(size.width))x\(Int(size.height))")
print("")

let reader = try! AVAssetReader(asset: asset)
let outputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
]
let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()

var allFrames: [FrameAngles] = []
var frameIndex = 0
let sampleEvery = 3

while let sampleBuffer = output.copyNextSampleBuffer() {
    frameIndex += 1
    if frameIndex % sampleEvery != 0 { continue }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
    let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

    let request = VNDetectHumanBodyPoseRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    try? handler.perform([request])

    guard let observation = request.results?.first else { continue }

    func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let p = try? observation.recognizedPoint(joint), p.confidence > 0.3 else { return nil }
        return p.location
    }

    let rShoulder = point(.rightShoulder)
    let rElbow = point(.rightElbow)
    let rWrist = point(.rightWrist)
    let lShoulder = point(.leftShoulder)
    let lElbow = point(.leftElbow)
    let lWrist = point(.leftWrist)
    let rHip = point(.rightHip)
    let rKnee = point(.rightKnee)
    let rAnkle = point(.rightAnkle)
    let lHip = point(.leftHip)
    let lKnee = point(.leftKnee)
    let lAnkle = point(.leftAnkle)
    let nose = point(.nose)

    var rElbowAngle: Double? = nil
    if let s = rShoulder, let e = rElbow, let w = rWrist {
        rElbowAngle = angleBetween(a: s, vertex: e, c: w)
    }

    var lElbowAngle: Double? = nil
    if let s = lShoulder, let e = lElbow, let w = lWrist {
        lElbowAngle = angleBetween(a: s, vertex: e, c: w)
    }

    var rKneeAngle: Double? = nil
    if let h = rHip, let k = rKnee, let a = rAnkle {
        rKneeAngle = angleBetween(a: h, vertex: k, c: a)
    }

    var lKneeAngle: Double? = nil
    if let h = lHip, let k = lKnee, let a = lAnkle {
        lKneeAngle = angleBetween(a: h, vertex: k, c: a)
    }

    var relHeight: Double? = nil
    if let w = rWrist, let n = nose {
        relHeight = Double(w.y - n.y)
    } else if let w = lWrist, let n = nose {
        relHeight = Double(w.y - n.y)
    }

    var shoulderAlign: Double? = nil
    if let l = lShoulder, let r = rShoulder {
        shoulderAlign = atan2(Double(r.y - l.y), Double(r.x - l.x)) * 180.0 / .pi
    }

    let shootingElbow = rElbowAngle ?? lElbowAngle
    let kneeAvg: Double? = {
        let vals = [rKneeAngle, lKneeAngle].compactMap { $0 }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }()

    var phase = "idle"
    if let k = kneeAvg, k < 130 {
        phase = "load"
    }
    if let e = shootingElbow, (75...110).contains(e) {
        phase = "set point"
    }
    if let e = shootingElbow, e > 110, let rh = relHeight, rh > 0 {
        phase = "release"
    }
    if let e = shootingElbow, e > 150 {
        phase = "follow through"
    }

    let frame = FrameAngles(
        time: timestamp,
        phase: phase,
        rightElbow: rElbowAngle,
        leftElbow: lElbowAngle,
        rightKnee: rKneeAngle,
        leftKnee: lKneeAngle,
        releaseHeight: relHeight,
        shoulderAlignment: shoulderAlign
    )
    allFrames.append(frame)
}

reader.cancelReading()

guard !allFrames.isEmpty else {
    print("No poses detected in any frame.")
    exit(1)
}

print("Detected poses in \(allFrames.count) frames")
print("")

print("--- Frame-by-Frame Analysis ---")
func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}
print("\(pad("TIME", 8))\(pad("PHASE", 16))\(pad("R.ELBOW", 10))\(pad("L.ELBOW", 10))\(pad("R.KNEE", 10))\(pad("L.KNEE", 10))\(pad("REL.HT", 10))")
print(String(repeating: "-", count: 74))

for f in allFrames {
    let time = String(format: "%.2f", f.time)
    let re = f.rightElbow.map { String(format: "%.1f°", $0) } ?? "--"
    let le = f.leftElbow.map { String(format: "%.1f°", $0) } ?? "--"
    let rk = f.rightKnee.map { String(format: "%.1f°", $0) } ?? "--"
    let lk = f.leftKnee.map { String(format: "%.1f°", $0) } ?? "--"
    let rh = f.releaseHeight.map { String(format: "%+.3f", $0) } ?? "--"
    print("\(pad(time, 8))\(pad(f.phase, 16))\(pad(re, 10))\(pad(le, 10))\(pad(rk, 10))\(pad(lk, 10))\(pad(rh, 10))")
}

print("")
print("--- Shooting Arm Detection ---")
let rElbows = allFrames.compactMap { $0.rightElbow }
let lElbows = allFrames.compactMap { $0.leftElbow }
let rVariance = rElbows.count >= 2 ? {
    let mean = rElbows.reduce(0, +) / Double(rElbows.count)
    return rElbows.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(rElbows.count)
}() : 0.0
let lVariance = lElbows.count >= 2 ? {
    let mean = lElbows.reduce(0, +) / Double(lElbows.count)
    return lElbows.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lElbows.count)
}() : 0.0
let shootingArm = rVariance > lVariance ? "RIGHT" : "LEFT"
print("Right arm variance: \(String(format: "%.1f", rVariance)) | Left arm variance: \(String(format: "%.1f", lVariance))")
print("Likely shooting arm: \(shootingArm) (higher variance = more movement)")

print("")
print("--- Key Metrics ---")

let shootingElbows = shootingArm == "RIGHT" ? rElbows : lElbows
let knees = allFrames.compactMap { f -> Double? in
    let vals = [f.rightKnee, f.leftKnee].compactMap { $0 }
    guard !vals.isEmpty else { return nil }
    return vals.reduce(0, +) / Double(vals.count)
}

if !shootingElbows.isEmpty {
    let minE = shootingElbows.min()!
    let maxE = shootingElbows.max()!
    let avgE = shootingElbows.reduce(0, +) / Double(shootingElbows.count)
    let elbowDiffs: [Double] = shootingElbows.map { ($0 - avgE) * ($0 - avgE) }
    let sdE: Double = sqrt(elbowDiffs.reduce(0, +) / Double(shootingElbows.count))
    print("Shooting Elbow:")
    print("  Min: \(String(format: "%.1f°", minE)) | Max: \(String(format: "%.1f°", maxE)) | Avg: \(String(format: "%.1f°", avgE))")
    print("  SD: \(String(format: "%.1f°", sdE))", terminator: "")
    if sdE < 5 { print(" (Excellent consistency)") }
    else if sdE < 10 { print(" (Good consistency)") }
    else if sdE < 15 { print(" (Fair consistency)") }
    else { print(" (High variance — work on repeatability)") }

    let setFrames = allFrames.filter { $0.phase == "set point" }
    let setElbows = setFrames.compactMap { shootingArm == "RIGHT" ? $0.rightElbow : $0.leftElbow }
    if !setElbows.isEmpty {
        let avg = setElbows.reduce(0, +) / Double(setElbows.count)
        print("  At set point: \(String(format: "%.1f°", avg)) (ideal: 85-100°)")
    }

    let releaseFrames = allFrames.filter { $0.phase == "follow through" }
    let releaseElbows = releaseFrames.compactMap { shootingArm == "RIGHT" ? $0.rightElbow : $0.leftElbow }
    if !releaseElbows.isEmpty {
        let avg = releaseElbows.reduce(0, +) / Double(releaseElbows.count)
        print("  At follow-through: \(String(format: "%.1f°", avg)) (ideal: 150-170°)")
    }
}

if !knees.isEmpty {
    let minK = knees.min()!
    let maxK = knees.max()!
    let avgK = knees.reduce(0, +) / Double(knees.count)
    let kneeDiffs: [Double] = knees.map { ($0 - avgK) * ($0 - avgK) }
    let sdK: Double = sqrt(kneeDiffs.reduce(0, +) / Double(knees.count))
    print("Knee Bend:")
    print("  Min: \(String(format: "%.1f°", minK)) | Max: \(String(format: "%.1f°", maxK)) | Avg: \(String(format: "%.1f°", avgK))")
    print("  Deepest bend: \(String(format: "%.1f°", minK)) (ideal loading: 50-70°)")
    print("  SD: \(String(format: "%.1f°", sdK))")
}

let heights = allFrames.compactMap { $0.releaseHeight }
if !heights.isEmpty {
    let maxH = heights.max()!
    print("Release Height:")
    print("  Peak wrist height above nose: \(String(format: "%.3f", maxH)) (positive = above head)")
}

let phases = allFrames.map { $0.phase }
let phaseTransitions = zip(phases, phases.dropFirst()).filter { $0.0 != $0.1 }.map { "\($0.0) → \($0.1)" }
print("")
print("--- Phase Transitions ---")
if phaseTransitions.isEmpty {
    print("No phase transitions detected")
} else {
    for t in phaseTransitions {
        print("  \(t)")
    }
}

print("")
let elbowSD = shootingElbows.count >= 2 ? {
    let mean = shootingElbows.reduce(0, +) / Double(shootingElbows.count)
    return sqrt(shootingElbows.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(shootingElbows.count))
}() : 0.0
let kneeSD = knees.count >= 2 ? {
    let mean = knees.reduce(0, +) / Double(knees.count)
    return sqrt(knees.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(knees.count))
}() : 0.0
let avgSD = (elbowSD + kneeSD) / 2.0
let consistencyScore = max(0, min(100, 100 - avgSD * 4))
print("=== OVERALL FORM CONSISTENCY: \(Int(consistencyScore))/100 ===")
if consistencyScore >= 80 { print("Rating: Excellent") }
else if consistencyScore >= 60 { print("Rating: Good") }
else if consistencyScore >= 40 { print("Rating: Fair") }
else { print("Rating: Needs work") }
