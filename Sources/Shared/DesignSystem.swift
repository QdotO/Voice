import SwiftUI

/// Shared design constants and views for the app
public enum DesignSystem {
    // MARK: - Semantic colors

    public enum Surface {
        public static let canvas = Color(whisperHex: 0x0B0B0D)
        public static let surface = Color(whisperHex: 0x131316)
        public static let raised = Color(whisperHex: 0x1A1A1F)
        public static let inset = Color(whisperHex: 0x09090B)
    }

    public enum Text {
        public static let primary = Color(whisperHex: 0xF5F3F1)
        public static let secondary = Color(whisperHex: 0xA9A5A1)
        public static let tertiary = Color(whisperHex: 0x74716E)
    }

    public enum Stroke {
        public static let subtle = Color.white.opacity(0.10)
        public static let strong = Color.white.opacity(0.20)
    }

    public enum States {
        public static let active = Color(whisperHex: 0xFF6A32)
        public static let activeBright = Color(whisperHex: 0xFF9A62)
        public static let processing = Color(whisperHex: 0xF6A43A)
        public static let success = Color(whisperHex: 0x55C58A)
        public static let warning = Color(whisperHex: 0xE8B44C)
        public static let danger = Color(whisperHex: 0xF05D62)
        public static let info = Color(whisperHex: 0x75A7E8)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let control: CGFloat = 8
        public static let row: CGFloat = 12
        public static let card: CGFloat = 16
        public static let capsule: CGFloat = 24
    }

    public enum ControlHeight {
        public static let compact: CGFloat = 32
        public static let standard: CGFloat = 36
        public static let primary: CGFloat = 44
    }

    // MARK: - Compatibility aliases

    public static let backgroundGradient = LinearGradient(
        colors: [
            Surface.canvas,
            Surface.surface,
            Surface.canvas,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let accentGradient = LinearGradient(
        colors: [States.active, States.activeBright],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let cardBackground = Surface.surface
    public static let cardStroke = Stroke.subtle

    public enum CardLevel {
        case surface
        case raised
        case inset

        fileprivate var color: Color {
            switch self {
            case .surface: return Surface.surface
            case .raised: return Surface.raised
            case .inset: return Surface.inset
            }
        }
    }

    public enum ButtonVariant {
        case active
        case busy
        case destructive

        fileprivate var color: Color {
            switch self {
            case .active: return States.active
            case .busy: return States.processing
            case .destructive: return States.danger
            }
        }
    }

    public enum StatusRole {
        case active
        case processing
        case success
        case warning
        case danger
        case info

        fileprivate var color: Color {
            switch self {
            case .active: return States.active
            case .processing: return States.processing
            case .success: return States.success
            case .warning: return States.warning
            case .danger: return States.danger
            case .info: return States.info
            }
        }
    }

    public struct WhisperCardModifier: ViewModifier {
        public let level: CardLevel
        public let isSelected: Bool

        public init(level: CardLevel = .surface, isSelected: Bool = false) {
            self.level = level
            self.isSelected = isSelected
        }

        public func body(content: Content) -> some View {
            content
                .background(level.color)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(
                            isSelected ? Stroke.strong : Stroke.subtle,
                            lineWidth: isSelected ? 1 : 0.5
                        )
                )
        }
    }

    public struct WhisperPrimaryButtonStyle: ButtonStyle {
        public let variant: ButtonVariant
        public let isBusy: Bool

        public init(variant: ButtonVariant = .active, isBusy: Bool = false) {
            self.variant = variant
            self.isBusy = isBusy
        }

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(Text.primary)
                .frame(minHeight: ControlHeight.primary)
                .padding(.horizontal, Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(isBusy ? States.processing : variant.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(Color.white.opacity(configuration.isPressed ? 0.35 : 0.20), lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
        }
    }

    public struct WhisperIconButtonStyle: ButtonStyle {
        public let isDestructive: Bool

        public init(isDestructive: Bool = false) {
            self.isDestructive = isDestructive
        }

        public func makeBody(configuration: Configuration) -> some View {
            IconButtonBody(
                configuration: configuration,
                tint: isDestructive ? States.danger : Text.primary
            )
        }
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var isHovered = false

        init(configuration: ButtonStyle.Configuration, tint: Color) {
            self.configuration = configuration
            self.tint = tint
        }

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .frame(width: ControlHeight.compact, height: ControlHeight.compact)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? Stroke.strong
                                : (isHovered ? Stroke.subtle : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(isHovered ? Stroke.strong : Color.clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .onHover { isHovered = $0 }
        }
    }

    public struct WhisperStatusChip: View {
        public let icon: String
        public let label: String
        public let role: StatusRole

        public init(icon: String, label: String, role: StatusRole) {
            self.icon = icon
            self.label = label
            self.role = role
        }

        public var body: some View {
            Label(label, systemImage: icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(Text.primary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: ControlHeight.standard)
                .background(role.color.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(role.color.opacity(0.45), lineWidth: 1))
        }
    }

    // MARK: - Modifiers

    public struct GlassCard: ViewModifier {
        public var cornerRadius: CGFloat

        public init(cornerRadius: CGFloat) {
            self.cornerRadius = cornerRadius
        }

        public func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial)
                .background(Surface.surface.opacity(0.88))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(cardStroke, lineWidth: 0.5)
                )
        }
    }
}

public extension View {
    func whisperCard(
        level: DesignSystem.CardLevel = .surface,
        isSelected: Bool = false
    ) -> some View {
        modifier(DesignSystem.WhisperCardModifier(level: level, isSelected: isSelected))
    }

    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(DesignSystem.GlassCard(cornerRadius: cornerRadius))
    }

    func mainBackground() -> some View {
        self.background(DesignSystem.backgroundGradient.ignoresSafeArea())
    }
}

public extension ButtonStyle where Self == DesignSystem.WhisperPrimaryButtonStyle {
    static func whisperPrimary(
        variant: DesignSystem.ButtonVariant = .active,
        isBusy: Bool = false
    ) -> DesignSystem.WhisperPrimaryButtonStyle {
        DesignSystem.WhisperPrimaryButtonStyle(variant: variant, isBusy: isBusy)
    }
}

public extension ButtonStyle where Self == DesignSystem.WhisperIconButtonStyle {
    static func whisperIconButton(
        isDestructive: Bool = false
    ) -> DesignSystem.WhisperIconButtonStyle {
        DesignSystem.WhisperIconButtonStyle(isDestructive: isDestructive)
    }
}

private extension Color {
    init(whisperHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
