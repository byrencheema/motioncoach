import SwiftUI

struct FormSummaryContent: View {
    let formStats: FormStats

    var body: some View {
        VStack(spacing: Spacing.md) {
            if let score = formStats.overallConsistencyScore {
                ConsistencyRingView(score: score)
                    .padding(.vertical, Spacing.md)
            }

            if let elbowSet = formStats.avgElbowAtSet {
                StatRow(
                    label: "Avg Elbow at Set",
                    value: "\(Int(elbowSet))°",
                    color: angleColor(elbowSet, ideal: 85...100)
                )
            }
            if let elbowRelease = formStats.avgElbowAtRelease {
                StatRow(
                    label: "Avg Elbow at Release",
                    value: "\(Int(elbowRelease))°",
                    color: angleColor(elbowRelease, ideal: 150...170)
                )
            }
            if let knee = formStats.avgKneeBend {
                StatRow(
                    label: "Avg Knee Bend",
                    value: "\(Int(knee))°",
                    color: angleColor(knee, ideal: 50...70)
                )
            }

            if let elbowSD = formStats.elbowConsistency {
                StatRow(
                    label: "Elbow Consistency",
                    value: consistencyLabel(elbowSD),
                    color: consistencyColor(elbowSD)
                )
            }
            if let kneeSD = formStats.kneeConsistency {
                StatRow(
                    label: "Knee Consistency",
                    value: consistencyLabel(kneeSD),
                    color: consistencyColor(kneeSD)
                )
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func angleColor(_ value: Double, ideal: ClosedRange<Double>) -> Color {
        if ideal.contains(value) { return Court.green }
        return Court.orange
    }

    private func consistencyLabel(_ sd: Double) -> String {
        if sd < 5 { return "Excellent" }
        if sd < 10 { return "Good" }
        if sd < 15 { return "Fair" }
        return "Work on it"
    }

    private func consistencyColor(_ sd: Double) -> Color {
        if sd < 5 { return Court.green }
        if sd < 10 { return Court.teal }
        if sd < 15 { return Court.orange }
        return Court.red
    }
}

struct ConsistencyRingView: View {
    let score: Double
    var size: CGFloat = 200
    var ringWidth: CGFloat = 10

    @State private var animatedTrim: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Court.cardBorder, lineWidth: ringWidth)

            Circle()
                .trim(from: 0, to: animatedTrim)
                .stroke(ringGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: Spacing.xs) {
                Text("\(Int(score))")
                    .font(.courtStatLarge)
                    .foregroundStyle(Court.textPrimary)
                Text("FORM")
                    .font(.courtCaption)
                    .foregroundStyle(Court.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                animatedTrim = CGFloat(min(score, 100)) / 100
            }
        }
    }

    private var ringGradient: LinearGradient {
        if score >= 80 {
            return LinearGradient(colors: [Court.green, Court.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return Court.flameGradient
    }
}
