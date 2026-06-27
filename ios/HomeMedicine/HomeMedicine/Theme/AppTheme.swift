import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.98, green: 0.98, blue: 0.98)
    static let cardBackground = Color.white
    static let primary = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let primaryDark = Color(red: 0.05, green: 0.63, blue: 0.45)
    static let primaryLight = Color(red: 0.93, green: 0.99, blue: 0.96)
    static let textPrimary = Color(red: 0.07, green: 0.09, blue: 0.15)
    static let textSecondary = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let textMuted = Color(red: 0.61, green: 0.64, blue: 0.69)
    static let border = Color(red: 0.90, green: 0.91, blue: 0.92)
    static let searchBackground = Color(red: 0.95, green: 0.96, blue: 0.97)

    static let normal = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let expiring = Color(red: 0.92, green: 0.70, blue: 0.03)
    static let expired = Color(red: 0.86, green: 0.15, blue: 0.15)
    static let depleted = Color(red: 0.55, green: 0.55, blue: 0.55)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let urgent = Color(red: 0.94, green: 0.27, blue: 0.27)

    static let cardRadius: CGFloat = 16
    static let chipRadius: CGFloat = 999
    static let minTouchTarget: CGFloat = 44
}

struct CardStyle: ViewModifier {
    var borderColor: Color = AppTheme.border

    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(borderColor.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

extension View {
    func cardStyle(borderColor: Color = AppTheme.border) -> some View {
        modifier(CardStyle(borderColor: borderColor))
    }
}
