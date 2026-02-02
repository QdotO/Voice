import SwiftUI

/// Shared design constants and views for the app
public enum DesignSystem {
    // MARK: - Colors

    public static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.05, blue: 0.1),  // Almost black
            Color(red: 0.1, green: 0.08, blue: 0.2),  // Deep purple tint
            Color(red: 0.05, green: 0.1, blue: 0.15),  // Deep blue tint
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let accentGradient = LinearGradient(
        colors: [Color.purple, Color.blue],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let cardBackground = Color.black.opacity(0.3)
    public static let cardStroke = Color.white.opacity(0.12)

    // MARK: - Modifiers

    public struct GlassCard: ViewModifier {
        public var cornerRadius: CGFloat

        public init(cornerRadius: CGFloat) {
            self.cornerRadius = cornerRadius
        }

        public func body(content: Content) -> some View {
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

public extension View {
    public func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(DesignSystem.GlassCard(cornerRadius: cornerRadius))
    }

    public func mainBackground() -> some View {
        self.background(DesignSystem.backgroundGradient.ignoresSafeArea())
    }
}
