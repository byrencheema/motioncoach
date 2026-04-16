import SwiftUI

struct CourtCard<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(isSelected ? Court.tealLight : Court.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(isSelected ? Court.teal : Court.cardBorder, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Court.cardShadow, radius: isSelected ? 12 : 6, y: isSelected ? 6 : 3)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
