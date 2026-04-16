import SwiftUI

struct CountdownOverlay: View {
    let onComplete: () -> Void

    @State private var currentValue = 3
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var isComplete = false

    var body: some View {
        ZStack {
            Court.cream.ignoresSafeArea()

            if !isComplete {
                Text(currentValue > 0 ? "\(currentValue)" : "GO!")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(currentValue > 0 ? Court.teal : Court.green)
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
        }
        .onAppear {
            runCountdown()
        }
    }

    private func runCountdown() {
        animateNumber()

        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.9) {
                currentValue = 3 - i
                animateNumber()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            isComplete = true
            onComplete()
        }
    }

    private func animateNumber() {
        scale = 0.5
        opacity = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
        }
    }
}
