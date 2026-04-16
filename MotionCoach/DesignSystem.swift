import SwiftUI

enum Court {
    static let cream = Color(hex: 0xF5F1EC)
    static let white = Color(hex: 0xFFFFFF)
    static let surface = Color(hex: 0xFAF8F5)
    static let cardBorder = Color(hex: 0xEBE7E2)

    static let textPrimary = Color(hex: 0x1A1A2E)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary = Color(hex: 0xBBB8B3)
    static let watermark = Color(hex: 0xE8E4DF)

    static let teal = Color(hex: 0x3ABFAD)
    static let tealLight = Color(hex: 0x3ABFAD).opacity(0.12)
    static let green = Color(hex: 0x34C759)
    static let red = Color(hex: 0xFF3B30)
    static let orange = Color(hex: 0xFF9500)

    static let flameOrange = teal
    static let black = cream

    static let flameGradient = LinearGradient(
        colors: [Color(hex: 0x3ABFAD), Color(hex: 0x2DA89A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let celebrationGradient = RadialGradient(
        colors: [Color(hex: 0x3ABFAD).opacity(0.08), Color.clear],
        center: .top,
        startRadius: 0,
        endRadius: 350
    )

    static let cardShadow = Color(hex: 0x1A1A2E).opacity(0.06)
    static let cyan = teal
}

extension Font {
    static let courtDisplayLarge = Font.system(size: 44, weight: .black, design: .rounded)
    static let courtDisplayMedium = Font.system(size: 34, weight: .bold, design: .rounded)
    static let courtHeadingLarge = Font.system(size: 28, weight: .bold)
    static let courtHeadingMedium = Font.system(size: 22, weight: .semibold)
    static let courtHeadingSmall = Font.system(size: 17, weight: .semibold)
    static let courtBodyLarge = Font.system(size: 17, weight: .regular)
    static let courtBodySmall = Font.system(size: 15, weight: .regular)
    static let courtCaption = Font.system(size: 12, weight: .semibold)
    static let courtStat = Font.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit()
    static let courtStatLarge = Font.system(size: 56, weight: .black, design: .rounded).monospacedDigit()
    static let courtMono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let courtWatermark = Font.system(size: 72, weight: .black, design: .rounded)
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
