import AudioToolbox
import AVFoundation
import Charts
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    enum Screen: Hashable {
        case start
        case live(DrillConfiguration)
        case summary(DrillSession)
        case history
    }

    @State private var path: [Screen] = []

    var body: some View {
        NavigationStack(path: $path) {
            StartScreen(
                onStart: { configuration in path.append(.live(configuration)) },
                onHistory: { path.append(.history) }
            )
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .start:
                    StartScreen(
                        onStart: { configuration in path.append(.live(configuration)) },
                        onHistory: { path.append(.history) }
                    )
                case .live(let configuration):
                    LiveDrillScreen(configuration: configuration) { session in
                        path.removeAll()
                        path.append(.summary(session))
                    }
                case .summary(let session):
                    SessionSummaryScreen(session: session) {
                        path.removeAll()
                    }
                case .history:
                    HistoryScreen()
                }
            }
        }
    }
}

struct StartScreen: View {
    @State private var selectedKind: DrillKind = .freeShoot
    let onStart: (DrillConfiguration) -> Void
    let onHistory: () -> Void

    private let drillKinds: [DrillKind] = [
        .freeShoot,
        .makeTarget(10),
        .makeTarget(25),
        .timed(120),
        .timed(300)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MotionCoach")
                    .font(.largeTitle.weight(.bold))
                Text("Pick a drill, face the hoop, and shoot.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(drillKinds, id: \.self) { kind in
                    DrillChoiceButton(kind: kind, isSelected: selectedKind == kind) {
                        selectedKind = kind
                    }
                }
            }

            Spacer()

            Button {
                onStart(DrillConfiguration(kind: selectedKind))
            } label: {
                Text("Start Drill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("History", action: onHistory)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(24)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DrillChoiceButton: View {
    let kind: DrillKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(isSelected ? Color.green.opacity(0.16) : Color(.secondarySystemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        switch kind {
        case .freeShoot:
            return "Count every rep"
        case .makeTarget(let target):
            return "\(target) makes to finish"
        case .timed(let duration):
            return "\(Int(duration / 60)) minutes"
        }
    }
}

struct LiveDrillScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var cameraManager = CameraManager()
    @State private var startedAt = Date()
    @State private var now = Date()
    @State private var didFinish = false

    let configuration: DrillConfiguration
    let onFinished: (DrillSession) -> Void

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()

            Color.black.opacity(cameraManager.cameraStatus == .authorized ? 0 : 0.82)
                .ignoresSafeArea()

            DetectionOverlay(detections: cameraManager.detections)
                .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    DrillHUD(stats: cameraManager.stats, progressText: progressText)
                    Spacer()
                    Button("End Drill") {
                        finish()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()

                Spacer()

                VStack(spacing: 6) {
                    if let message = statusMessage {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    DebugOverlay(info: cameraManager.debugInfo, modelStatus: cameraManager.modelStatus)
                }
                .padding()
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startedAt = Date()
            cameraManager.resetStats()
            cameraManager.configure {
                AudioServicesPlaySystemSound(1057)
            }
        }
        .onDisappear {
            cameraManager.stop()
        }
        .onReceive(timer) { value in
            now = value
            finishIfNeeded()
        }
    }

    private var statusMessage: String? {
        if cameraManager.cameraStatus == .denied {
            return "Camera access is off. Enable camera access in Settings."
        }

        if cameraManager.cameraStatus == .unavailable {
            return "No rear camera is available."
        }

        return cameraManager.modelStatus.message
    }

    private var progressText: String? {
        switch configuration.kind {
        case .freeShoot:
            return nil
        case .makeTarget(let target):
            return "\(max(0, target - cameraManager.stats.makes)) makes left"
        case .timed(let duration):
            let remaining = max(0, Int(duration - now.timeIntervalSince(startedAt)))
            return "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
        }
    }

    private func finishIfNeeded() {
        guard !didFinish else { return }

        switch configuration.kind {
        case .freeShoot:
            break
        case .makeTarget(let target):
            if cameraManager.stats.makes >= target {
                finish()
            }
        case .timed(let duration):
            if now.timeIntervalSince(startedAt) >= duration {
                finish()
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        cameraManager.stop()

        let session = DrillSession(
            startedAt: startedAt,
            endedAt: Date(),
            drillKind: configuration.kind,
            stats: cameraManager.stats
        )
        sessionStore.add(session)
        onFinished(session)
    }
}

struct DrillHUD: View {
    let stats: DrillStats
    let progressText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                StatPill(label: "Makes", value: "\(stats.makes)")
                StatPill(label: "Attempts", value: "\(stats.attempts)")
                StatPill(label: "FG%", value: "\(Int(stats.fieldGoalPercentage.rounded()))")
            }

            if let progressText {
                Text(progressText)
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
        }
        .frame(minWidth: 76, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SessionSummaryScreen: View {
    let session: DrillSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            SummaryCard(session: session)

            ShareLink(item: ImageTransferable(image: SummaryCardRenderer.image(for: session)), preview: SharePreview("MotionCoach Summary", image: Image(uiImage: SummaryCardRenderer.image(for: session)))) {
                Label("Share Summary", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Done", action: onDone)
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(24)
        .navigationBarBackButtonHidden()
    }
}

struct SummaryCard: View {
    let session: DrillSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(session.drillKind.summaryTitle)
                .font(.title.weight(.bold))
            Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                SummaryMetric(label: "Makes", value: "\(session.stats.makes)")
                SummaryMetric(label: "Attempts", value: "\(session.stats.attempts)")
                SummaryMetric(label: "FG%", value: "\(Int(session.stats.fieldGoalPercentage.rounded()))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SummaryMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            if sessionStore.sessions.isEmpty {
                ContentUnavailableView("No Sessions Yet", systemImage: "basketball", description: Text("Your completed drills will appear here."))
            } else {
                Section {
                    Chart(sessionStore.sessions.reversed()) { session in
                        LineMark(
                            x: .value("Date", session.endedAt),
                            y: .value("FG%", session.stats.fieldGoalPercentage)
                        )
                        PointMark(
                            x: .value("Date", session.endedAt),
                            y: .value("FG%", session.stats.fieldGoalPercentage)
                        )
                    }
                    .frame(height: 180)
                    .chartYScale(domain: 0...100)
                }

                Section("Sessions") {
                    ForEach(sessionStore.sessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.drillKind.summaryTitle)
                                    .font(.headline)
                                Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(Int(session.stats.fieldGoalPercentage.rounded()))%")
                                .font(.title3.weight(.bold).monospacedDigit())
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

enum SummaryCardRenderer {
    @MainActor
    static func image(for session: DrillSession) -> UIImage {
        let renderer = ImageRenderer(content: SummaryCard(session: session).frame(width: 640).padding(24))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage ?? UIImage()
    }
}

struct ImageTransferable: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
    }
}

struct DebugOverlay: View {
    let info: DebugInfo
    let modelStatus: ModelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MODEL: \(modelStatusText)")
                .foregroundStyle(modelStatus == .loaded ? .green : .red)
            Text("FRAMES: \(info.framesProcessed)")
            Text("DETECTIONS: \(info.detectionCount)")
            HStack(spacing: 12) {
                Label(info.ballDetected ? String(format: "%.0f%%", info.ballConfidence * 100) : "--",
                      systemImage: "circle.fill")
                    .foregroundStyle(info.ballDetected ? .orange : .gray)
                Label(info.basketDetected ? String(format: "%.0f%%", info.basketConfidence * 100) : "--",
                      systemImage: "square.fill")
                    .foregroundStyle(info.basketDetected ? .cyan : .gray)
            }
            if let error = info.lastError {
                Text("ERR: \(error)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.monospaced())
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modelStatusText: String {
        switch modelStatus {
        case .loaded: return "LOADED"
        case .missing: return "MISSING"
        case .notLoaded: return "NOT LOADED"
        case .failed(let msg): return "FAILED - \(msg)"
        }
    }
}

struct DetectionOverlay: View {
    let detections: [Detection]

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { detection in
                let rect = visionToScreen(detection.boundingBox, in: geo.size)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(detection.detectedClass == .ball ? Color.orange : Color.cyan, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .overlay {
                        Text(detection.detectedClass == .ball ? "Ball" : "Hoop")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(detection.detectedClass == .ball ? Color.orange : Color.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .position(x: rect.midX, y: rect.minY - 10)
                    }
            }
        }
    }

    private func visionToScreen(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.origin.x * size.width,
            y: (1 - box.origin.y - box.height) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-sessions.json")))
}
