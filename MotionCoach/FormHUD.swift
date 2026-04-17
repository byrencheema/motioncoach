import SwiftUI

struct FormHUD: View {
    let angles: FormAngles
    let phase: ShotPhase
    let formStats: FormStats
    let shotStats: DrillStats

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                PhaseIndicator(phase: phase)
                Spacer()
                Text("\(formStats.repCount) reps")
                    .font(.courtMono)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            HStack(spacing: Spacing.sm) {
                AnglePill(label: "ELBOW", value: angles.elbowAngle, idealRange: 85...170)
                AnglePill(label: "KNEE", value: angles.kneeBend, idealRange: 50...170)
                if let score = formStats.overallConsistencyScore {
                    CourtPill(label: "FORM", value: "\(Int(score))", accent: consistencyColor(score))
                }
            }
        }
    }

    private func consistencyColor(_ score: Double) -> Color {
        if score >= 80 { return Court.green }
        if score >= 60 { return Court.orange }
        return Court.red
    }
}

struct PhaseIndicator: View {
    let phase: ShotPhase

    var body: some View {
        Text(phaseLabel.uppercased())
            .font(.courtCaption)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(phaseColor.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var phaseLabel: String {
        switch phase {
        case .idle: return "Ready"
        case .load: return "Loading"
        case .setPoint: return "Set"
        case .release: return "Release"
        case .followThrough: return "Follow Through"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .idle: return .gray
        case .load: return Court.orange
        case .setPoint: return Court.teal
        case .release, .followThrough: return Court.green
        }
    }
}

struct AnglePill: View {
    let label: String
    let value: Double?
    let idealRange: ClosedRange<Double>

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(label)
                .font(.courtCaption)
                .foregroundStyle(.white.opacity(0.7))
            Text(value.map { "\(Int($0))°" } ?? "--")
                .font(.courtStat)
                .foregroundStyle(valueColor)
        }
        .frame(minWidth: 76)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var valueColor: Color {
        guard let v = value else { return .white }
        if idealRange.contains(v) { return Court.green }
        let lowerDist = max(0, idealRange.lowerBound - v)
        let upperDist = max(0, v - idealRange.upperBound)
        let dist = max(lowerDist, upperDist)
        return dist <= 15 ? Court.orange : Court.red
    }
}
