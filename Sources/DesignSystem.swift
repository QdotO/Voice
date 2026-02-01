import SwiftUI

/// Shared design constants and views for the app
enum DesignSystem {
    // MARK: - Colors

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.05, blue: 0.1),  // Almost black
            Color(red: 0.1, green: 0.08, blue: 0.2),  // Deep purple tint
            Color(red: 0.05, green: 0.1, blue: 0.15),  // Deep blue tint
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [Color.purple, Color.blue],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let cardBackground = Color.black.opacity(0.3)
    static let cardStroke = Color.white.opacity(0.12)

    // MARK: - Modifiers

    struct GlassCard: ViewModifier {
        var cornerRadius: CGFloat

        func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.2))  // Darken it a bit
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(cardStroke, lineWidth: 0.5)
                )
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(DesignSystem.GlassCard(cornerRadius: cornerRadius))
    }

    func mainBackground() -> some View {
        self.background(DesignSystem.backgroundGradient.ignoresSafeArea())
    }
}
