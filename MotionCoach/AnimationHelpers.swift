import SwiftUI

struct CountUpModifier: AnimatableModifier {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text("\(Int(value))")
    }
}

struct MakeFlashOverlay: View {
    @Binding var trigger: Int

    @State private var flash = false

    var body: some View {
        Court.flameOrange
            .opacity(flash ? 0.15 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: trigger) { _ in
                flash = true
                withAnimation(.easeOut(duration: 0.3)) {
                    flash = false
                }
            }
    }
}

struct StaggeredAppear: ViewModifier {
    let index: Int
    let baseDelay: Double

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .onAppear {
                withAnimation(
                    .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(baseDelay + Double(index) * 0.05)
                ) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int, baseDelay: Double = 0) -> some View {
        modifier(StaggeredAppear(index: index, baseDelay: baseDelay))
    }
}
