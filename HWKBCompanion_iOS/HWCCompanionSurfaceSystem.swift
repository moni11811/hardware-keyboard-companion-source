import SwiftUI

enum HWCCompanionActionRole {
    case primary
    case secondary
    case destructive
}

struct HWCCompanionGlassGroup<Content: View>: View {
    let spacing: CGFloat
    private let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(spacing: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct HWCCompanionFallbackButtonStyle: ButtonStyle {
    let role: HWCCompanionActionRole
    let tint: Color
    let reduceMotion: Bool
    let highContrast: Bool
    let differentiateWithoutColor: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(configuration: configuration))
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: highContrast || differentiateWithoutColor ? 1.5 : 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        role == .destructive ? .red : .primary
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch role {
        case .primary:
            return tint.opacity(configuration.isPressed ? 0.42 : 0.32)
        case .secondary:
            return Color.primary.opacity(configuration.isPressed ? 0.16 : 0.10)
        case .destructive:
            return Color.red.opacity(configuration.isPressed ? 0.20 : 0.12)
        }
    }

    private var borderColor: Color {
        switch role {
        case .primary:
            return tint.opacity(highContrast ? 1 : 0.78)
        case .secondary:
            return Color.primary.opacity(highContrast ? 0.52 : 0.24)
        case .destructive:
            return Color.red.opacity(highContrast ? 1 : 0.72)
        }
    }
}

private struct HWCCompanionActionModifier: ViewModifier {
    let role: HWCCompanionActionRole
    let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            switch role {
            case .primary:
                content
                    .controlSize(.small)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            case .secondary:
                content
                    .controlSize(.small)
                    .buttonStyle(.glass)
            case .destructive:
                content
                    .controlSize(.small)
                    .buttonStyle(.glass)
                    .tint(.red)
            }
        } else {
            content
                .controlSize(.small)
                .buttonStyle(
                    HWCCompanionFallbackButtonStyle(
                        role: role,
                        tint: tint,
                        reduceMotion: reduceMotion,
                        highContrast: colorSchemeContrast == .increased,
                        differentiateWithoutColor: differentiateWithoutColor
                    )
                )
        }
    }
}

extension View {
    func hwcCompanionActionStyle(
        _ role: HWCCompanionActionRole,
        tint: Color = .accentColor
    ) -> some View {
        modifier(HWCCompanionActionModifier(role: role, tint: tint))
    }
}
