import SwiftUI

struct CourtPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.courtHeadingSmall)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Court.flameGradient)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .shadow(color: Court.teal.opacity(configuration.isPressed ? 0.3 : 0.15), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CourtSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.courtHeadingSmall)
            .foregroundStyle(Court.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Court.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(Court.cardBorder, lineWidth: 1)
            )
            .shadow(color: Court.cardShadow, radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CourtDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.courtHeadingSmall)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .frame(height: 48)
            .background(Court.red)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .shadow(color: Court.red.opacity(0.2), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
