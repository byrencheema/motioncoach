import SwiftUI

struct FormHUD: View {
    let angles: FormAngles
    let phase: ShotPhase
    let formStats: FormStats
    let shotStats: DrillStats

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("\(formStats.repCount) reps")
                .font(.courtMono)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            Spacer()

            if let score = formStats.overallConsistencyScore {
                CourtPill(label: "FORM", value: "\(Int(score))", accent: consistencyColor(score))
            }
        }
    }

    private func consistencyColor(_ score: Double) -> Color {
        if score >= 80 { return Court.green }
        if score >= 60 { return Court.orange }
        return Court.red
    }
}
