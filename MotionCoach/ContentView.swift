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

// MARK: - Start Screen

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
        ZStack {
            Court.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Court.teal)
                        .staggeredAppear(index: 0)

                    Text("MotionCoach")
                        .font(.courtDisplayLarge)
                        .foregroundStyle(Court.textPrimary)
                        .staggeredAppear(index: 1)

                    Text("Pick a drill. Face the hoop. Shoot.")
                        .font(.courtBodySmall)
                        .foregroundStyle(Court.textSecondary)
                        .staggeredAppear(index: 2)
                }
                .padding(.top, Spacing.xl)

                Spacer()

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(Array(drillKinds.enumerated()), id: \.element) { index, kind in
                        DrillChoiceButton(kind: kind, isSelected: selectedKind == kind) {
                            let generator = UISelectionFeedbackGenerator()
                            generator.selectionChanged()
                            selectedKind = kind
                        }
                        .staggeredAppear(index: index + 3, baseDelay: 0.1)
                    }
                }
                .padding(.horizontal, Spacing.lg)

                Spacer()

                VStack(spacing: Spacing.md) {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onStart(DrillConfiguration(kind: selectedKind))
                    } label: {
                        Text("Start Drill")
                    }
                    .buttonStyle(CourtPrimaryButtonStyle())
                    .staggeredAppear(index: 8, baseDelay: 0.2)

                    Button(action: onHistory) {
                        Text("History")
                    }
                    .buttonStyle(CourtSecondaryButtonStyle())
                    .staggeredAppear(index: 9, baseDelay: 0.2)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DrillChoiceButton: View {
    let kind: DrillKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CourtCard(isSelected: isSelected) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Image(systemName: kind.sfSymbol)
                        .font(.system(size: 22))
                        .foregroundStyle(Court.teal)

                    Text(kind.title)
                        .font(.courtHeadingSmall)
                        .foregroundStyle(Court.textPrimary)

                    Text(subtitle)
                        .font(.courtBodySmall)
                        .foregroundStyle(Court.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .padding(Spacing.base)
            }
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

// MARK: - Live Drill Screen

struct LiveDrillScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var cameraManager = CameraManager()
    @State private var startedAt = Date()
    @State private var now = Date()
    @State private var didFinish = false
    @State private var showCountdown = true
    @State private var makeFlashCount = 0
    @State private var makePopScale: CGFloat = 1.0
    @State private var showDebug = false

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

            MakeFlashOverlay(trigger: $makeFlashCount)

            VStack {
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                    .ignoresSafeArea()

                    VStack(spacing: Spacing.sm) {
                        DrillHUD(
                            stats: cameraManager.stats,
                            progressText: progressText,
                            makePopScale: makePopScale
                        )
                        .onTapGesture(count: 3) {
                            showDebug.toggle()
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xs)
                }

                Spacer()

                VStack(spacing: Spacing.sm) {
                    if let message = statusMessage {
                        Text(message)
                            .font(.courtCaption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(Spacing.md)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }

                    if showDebug {
                        DebugOverlay(info: cameraManager.debugInfo, modelStatus: cameraManager.modelStatus)
                    }
                }
                .padding(.horizontal, Spacing.lg)

                Button("End Drill") {
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    finish()
                }
                .buttonStyle(CourtDestructiveButtonStyle())
                .padding(.bottom, Spacing.lg)
            }

            if showCountdown {
                CountdownOverlay {
                    showCountdown = false
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startedAt = Date()
            cameraManager.resetStats()
            cameraManager.configure {
                AudioServicesPlaySystemSound(1057)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                makeFlashCount += 1
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    makePopScale = 1.3
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.15)) {
                    makePopScale = 1.0
                }
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
            return "\(max(0, target - cameraManager.stats.makes)) left"
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
            if cameraManager.stats.makes >= target { finish() }
        case .timed(let duration):
            if now.timeIntervalSince(startedAt) >= duration { finish() }
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
    var makePopScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                CourtPill(label: "MAKES", value: "\(stats.makes)", accent: Court.green)
                    .scaleEffect(makePopScale)
                CourtPill(label: "ATT", value: "\(stats.attempts)")
                CourtPill(label: "FG%", value: "\(Int(stats.fieldGoalPercentage.rounded()))", accent: fgColor)
            }

            if let progressText {
                Text(progressText)
                    .font(.courtMono)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
        }
    }

    private var fgColor: Color {
        let pct = stats.fieldGoalPercentage
        if pct >= 50 { return Court.green }
        if pct >= 30 { return Court.orange }
        return Court.red
    }
}

struct CourtPill: View {
    let label: String
    let value: String
    var accent: Color = .white

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(label)
                .font(.courtCaption)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.courtStat)
                .foregroundStyle(accent)
        }
        .frame(minWidth: 76)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}

// MARK: - Session Summary

struct SessionSummaryScreen: View {
    let session: DrillSession
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Court.cream.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer()

                Text(session.drillKind.summaryTitle)
                    .font(.courtHeadingLarge)
                    .foregroundStyle(Court.textPrimary)
                    .staggeredAppear(index: 0)

                Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.courtBodySmall)
                    .foregroundStyle(Court.textSecondary)
                    .staggeredAppear(index: 1)

                FGRingView(percentage: session.stats.fieldGoalPercentage)
                    .padding(.vertical, Spacing.lg)
                    .staggeredAppear(index: 2, baseDelay: 0.1)

                VStack(spacing: Spacing.md) {
                    StatRow(label: "Makes", value: "\(session.stats.makes)", color: Court.teal)
                    StatRow(label: "Attempts", value: "\(session.stats.attempts)")
                    StatRow(label: "Duration", value: session.formattedDuration)
                }
                .padding(.horizontal, Spacing.lg)
                .staggeredAppear(index: 3, baseDelay: 0.2)

                Spacer()

                VStack(spacing: Spacing.md) {
                    ShareLink(
                        item: ImageTransferable(image: SummaryCardRenderer.image(for: session)),
                        preview: SharePreview("MotionCoach Summary", image: Image(uiImage: SummaryCardRenderer.image(for: session)))
                    ) {
                        Text("Share Summary")
                            .font(.courtHeadingSmall)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Court.flameGradient)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                            .shadow(color: Court.teal.opacity(0.15), radius: 12, y: 6)
                    }

                    Button("Done", action: onDone)
                        .buttonStyle(CourtSecondaryButtonStyle())
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
                .staggeredAppear(index: 4, baseDelay: 0.3)
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = Court.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.courtBodyLarge)
                .foregroundStyle(Court.textSecondary)
            Spacer()
            Text(value)
                .font(.courtStat)
                .foregroundStyle(color)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.md)
        .background(Court.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Court.cardBorder, lineWidth: 1)
        )
    }
}

struct SummaryMetric: View {
    let label: String
    let value: String
    var color: Color = Court.textPrimary

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.courtStat)
                .foregroundStyle(color)
            Text(label)
                .font(.courtCaption)
                .foregroundStyle(Court.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - History

struct HistoryScreen: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        ZStack {
            Court.cream.ignoresSafeArea()

            if sessionStore.sessions.isEmpty {
                VStack(spacing: Spacing.base) {
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Court.textTertiary)
                    Text("No Sessions Yet")
                        .font(.courtHeadingLarge)
                        .foregroundStyle(Court.textSecondary)
                    Text("Complete your first drill to start tracking.")
                        .font(.courtBodySmall)
                        .foregroundStyle(Court.textTertiary)
                }
            } else {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("SHOOTING TREND")
                                .font(.courtCaption)
                                .foregroundStyle(Court.textSecondary)

                            Chart(sessionStore.sessions.reversed()) { session in
                                AreaMark(
                                    x: .value("Date", session.endedAt),
                                    y: .value("FG%", session.stats.fieldGoalPercentage)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Court.teal.opacity(0.2), Court.teal.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)

                                LineMark(
                                    x: .value("Date", session.endedAt),
                                    y: .value("FG%", session.stats.fieldGoalPercentage)
                                )
                                .foregroundStyle(Court.teal)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)

                                PointMark(
                                    x: .value("Date", session.endedAt),
                                    y: .value("FG%", session.stats.fieldGoalPercentage)
                                )
                                .foregroundStyle(Court.teal)
                                .symbolSize(40)

                                RuleMark(y: .value("50%", 50))
                                    .foregroundStyle(Court.textTertiary.opacity(0.3))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                            .chartYScale(domain: 0...100)
                            .chartXAxis {
                                AxisMarks { _ in
                                    AxisValueLabel()
                                        .foregroundStyle(Court.textTertiary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { _ in
                                    AxisGridLine()
                                        .foregroundStyle(Court.cardBorder)
                                    AxisValueLabel()
                                        .foregroundStyle(Court.textTertiary)
                                }
                            }
                            .frame(height: 220)
                        }
                        .padding(Spacing.base)
                        .background(Court.white)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .shadow(color: Court.cardShadow, radius: 8, y: 4)

                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("SESSIONS")
                                .font(.courtCaption)
                                .foregroundStyle(Court.textSecondary)

                            ForEach(sessionStore.sessions) { session in
                                SessionRow(session: session)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                }
            }
        }
        .navigationTitle("History")
    }
}

struct SessionRow: View {
    let session: DrillSession

    var body: some View {
        HStack(spacing: Spacing.base) {
            Image(systemName: session.drillKind.sfSymbol)
                .font(.system(size: 18))
                .foregroundStyle(Court.teal)
                .frame(width: 40, height: 40)
                .background(Court.tealLight)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session.drillKind.summaryTitle)
                    .font(.courtHeadingSmall)
                    .foregroundStyle(Court.textPrimary)
                Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.courtBodySmall)
                    .foregroundStyle(Court.textSecondary)
            }

            Spacer()

            Text("\(Int(session.stats.fieldGoalPercentage.rounded()))%")
                .font(.courtStat)
                .foregroundStyle(fgColor)
        }
        .padding(Spacing.base)
        .background(Court.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Court.cardBorder, lineWidth: 1)
        )
        .shadow(color: Court.cardShadow, radius: 6, y: 3)
    }

    private var fgColor: Color {
        let pct = session.stats.fieldGoalPercentage
        if pct >= 50 { return Court.green }
        if pct >= 30 { return Court.orange }
        return Court.red
    }
}

// MARK: - Overlays

struct DebugOverlay: View {
    let info: DebugInfo
    let modelStatus: ModelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("MODEL: \(modelStatusText)")
                .foregroundStyle(modelStatus == .loaded ? Court.green : Court.red)
            Text("FRAMES: \(info.framesProcessed)")
            Text("DETECTIONS: \(info.detectionCount)")
            HStack(spacing: Spacing.md) {
                Label(info.ballDetected ? String(format: "%.0f%%", info.ballConfidence * 100) : "--",
                      systemImage: "circle.fill")
                    .foregroundStyle(info.ballDetected ? Court.orange : Court.textTertiary)
                Label(info.basketDetected ? String(format: "%.0f%%", info.basketConfidence * 100) : "--",
                      systemImage: "square.fill")
                    .foregroundStyle(info.basketDetected ? Court.teal : Court.textTertiary)
                Label(info.ballInBasketDetected ? String(format: "%.0f%%", info.ballInBasketConfidence * 100) : "--",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(info.ballInBasketDetected ? Court.green : Court.textTertiary)
            }
            if let error = info.lastError {
                Text("ERR: \(error)")
                    .foregroundStyle(Court.red)
            }
        }
        .font(.courtMono)
        .foregroundStyle(.white.opacity(0.8))
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
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
            ForEach(detections.filter { Self.shouldShow($0) }) { detection in
                let rect = visionToScreen(detection.boundingBox, in: geo.size)
                let color = Self.color(for: detection.detectedClass)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 2.5)
                    .shadow(color: color.opacity(0.5), radius: 4)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private static func shouldShow(_ detection: Detection) -> Bool {
        switch detection.detectedClass {
        case .ball, .basket, .ballInBasket:
            return true
        case .player, .playerShooting:
            return false
        }
    }

    private static func color(for cls: DetectorClass) -> Color {
        switch cls {
        case .ball: return Court.orange
        case .ballInBasket: return Court.green
        case .player: return .blue
        case .basket: return Court.teal
        case .playerShooting: return .purple
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

// MARK: - Share

struct SummaryCard: View {
    let session: DrillSession

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Court.teal
                .frame(height: 4)

            Text("MOTIONCOACH")
                .font(.courtCaption)
                .foregroundStyle(Court.textSecondary)
                .kerning(2)

            Text("\(Int(session.stats.fieldGoalPercentage.rounded()))%")
                .font(.courtStatLarge)
                .foregroundStyle(Court.textPrimary)

            VStack(spacing: Spacing.md) {
                StatRow(label: "Makes", value: "\(session.stats.makes)", color: Court.teal)
                StatRow(label: "Attempts", value: "\(session.stats.attempts)")
            }

            VStack(spacing: Spacing.xs) {
                Text(session.drillKind.summaryTitle)
                    .font(.courtHeadingSmall)
                    .foregroundStyle(Court.textPrimary)
                Text(session.endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.courtBodySmall)
                    .foregroundStyle(Court.textSecondary)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Court.cream)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }
}

enum SummaryCardRenderer {
    @MainActor
    static func image(for session: DrillSession) -> UIImage {
        let renderer = ImageRenderer(
            content: SummaryCard(session: session)
                .frame(width: 400)
                .padding(Spacing.lg)
                .background(Court.cream)
        )
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

#Preview {
    ContentView()
        .environmentObject(SessionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-sessions.json")))
}
