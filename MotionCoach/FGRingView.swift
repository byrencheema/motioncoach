import SwiftUI

struct FGRingView: View {
    let percentage: Double
    var size: CGFloat = 200
    var ringWidth: CGFloat = 10

    @State private var animatedTrim: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Court.cardBorder, lineWidth: ringWidth)

            Circle()
                .trim(from: 0, to: animatedTrim)
                .stroke(
                    Court.flameGradient,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: Spacing.xs) {
                Text("\(Int(percentage.rounded()))")
                    .font(.courtStatLarge)
                    .foregroundStyle(Court.textPrimary)
                Text("FG%")
                    .font(.courtCaption)
                    .foregroundStyle(Court.textSecondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                animatedTrim = CGFloat(min(percentage, 100)) / 100
            }
        }
    }
}
