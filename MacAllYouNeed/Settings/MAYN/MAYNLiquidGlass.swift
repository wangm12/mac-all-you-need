import SwiftUI

// Native Liquid Glass helpers (Apple Technology Overview + Adopting Liquid Glass).
// macOS 26+: `glassEffect`, `GlassEffectContainer`, `.glass` button styles.
// macOS 14–25: `Material` fallbacks via `maynGlassSurface`.

enum MAYNLiquidGlass {
    @available(macOS 26.0, *)
    static func glass(for role: MAYNMaterial) -> Glass {
        switch role {
        case .chrome, .panel, .elevated:
            .regular
        case .overlay:
            .clear
        }
    }
}

struct MAYNGlassSurfaceModifier: ViewModifier {
    let role: MAYNMaterial
    let cornerRadius: CGFloat
    let showsBorder: Bool
    let showsShadow: Bool
    var morphID: String?
    var morphNamespace: Namespace.ID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            opaqueChrome(content: content, shape: shape)
        } else if #available(macOS 26.0, *) {
            glassChrome(content: content, shape: shape)
        } else {
            content
                .background(role.material, in: shape)
                .overlay {
                    if showsBorder {
                        shape.stroke(role.borderColor, lineWidth: 1)
                    }
                }
                .shadow(
                    color: Color.black.opacity(showsShadow ? role.shadowOpacity : 0),
                    radius: showsShadow ? role.shadowRadius : 0,
                    y: showsShadow ? role.shadowRadius / 2 : 0
                )
        }
    }

    @ViewBuilder
    private func opaqueChrome(content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(MAYNTheme.contentPanelElevated(colorScheme), in: shape)
            .overlay {
                if showsBorder {
                    shape.stroke(role.borderColor, lineWidth: 1)
                }
            }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glassChrome(content: Content, shape: RoundedRectangle) -> some View {
        let base = content
            .background {
                shape
                    .fill(Color.clear)
                    .glassEffect(MAYNLiquidGlass.glass(for: role), in: shape)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay {
                if showsBorder {
                    shape.stroke(role.borderColor, lineWidth: 1)
                }
            }
            .shadow(
                color: Color.black.opacity(showsShadow ? role.shadowOpacity : 0),
                radius: showsShadow ? role.shadowRadius : 0,
                y: showsShadow ? role.shadowRadius / 2 : 0
            )

        if let morphID, let morphNamespace {
            base.glassEffectID(morphID, in: morphNamespace)
        } else {
            base
        }
    }
}

/// Wraps floating panels with Liquid Glass behind content (sizes to content, never full-screen).
struct MAYNLiquidGlassPanel<Content: View>: View {
    let role: MAYNMaterial
    let cornerRadius: CGFloat
    let showsBorder: Bool
    let showsShadow: Bool
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                panelBackdrop(shape: shape)
            }
            .clipShape(shape)
            .overlay {
                if showsBorder {
                    shape.stroke(role.borderColor, lineWidth: 1)
                }
            }
            .shadow(
                color: Color.black.opacity(showsShadow ? role.shadowOpacity : 0),
                radius: showsShadow ? role.shadowRadius : 0,
                y: showsShadow ? role.shadowRadius / 2 : 0
            )
    }

    @ViewBuilder
    private func panelBackdrop(shape: RoundedRectangle) -> some View {
        if reduceTransparency {
            shape.fill(MAYNTheme.contentPanelElevated(colorScheme))
        } else if #available(macOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(MAYNLiquidGlass.glass(for: role), in: shape)
        } else {
            shape.fill(role.material)
        }
    }
}

extension View {
    /// Applies Apple's Liquid Glass on macOS 26+; `Material` fallback on earlier releases.
    func maynGlassSurface(
        _ role: MAYNMaterial = .panel,
        cornerRadius: CGFloat = MAYNControlMetrics.panelRadius,
        showsBorder: Bool = true,
        showsShadow: Bool = false,
        morphID: String? = nil,
        morphNamespace: Namespace.ID? = nil
    ) -> some View {
        modifier(
            MAYNGlassSurfaceModifier(
                role: role,
                cornerRadius: cornerRadius,
                showsBorder: showsBorder,
                showsShadow: showsShadow,
                morphID: morphID,
                morphNamespace: morphNamespace
            )
        )
    }

    @ViewBuilder
    func maynGlassButtonStyle(isProminent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            self
        }
    }
}

// MARK: - Selection (native Liquid Glass)

enum MAYNSelectionShape {
    case capsule
    case rounded(CGFloat)
}

/// Foreground for selectable rows/chips — glass selection keeps labels `.primary`, not inverted.
enum MAYNSelectionLabelStyle {
    static func foreground(isSelected: Bool, isDisabled: Bool = false) -> Color {
        if isDisabled { return .secondary }
        return isSelected ? .primary : .secondary
    }

    static func weight(isSelected: Bool) -> Font.Weight {
        isSelected ? .semibold : .regular
    }
}

/// Selected = `glassEffect` on macOS 26+; subtle `selected` fill on earlier macOS.
struct MAYNSelectionGlassBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    let shape: MAYNSelectionShape

    var body: some View {
        Group {
            if isSelected {
                selectedBackground
            } else if isHovering {
                hoverBackground
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var selectedBackground: some View {
        if #available(macOS 26.0, *) {
            switch shape {
            case .capsule:
                Color.clear.glassEffect(.regular, in: Capsule())
            case .rounded(let radius):
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        } else {
            switch shape {
            case .capsule:
                Capsule().fill(MAYNTheme.selected)
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(MAYNTheme.selected)
            }
        }
    }

    @ViewBuilder
    private var hoverBackground: some View {
        switch shape {
        case .capsule:
            Capsule().fill(MAYNTheme.hover)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(MAYNTheme.hover)
        }
    }
}

extension View {
    func maynSelectionBackground(
        isSelected: Bool,
        isHovering: Bool = false,
        shape: MAYNSelectionShape
    ) -> some View {
        background {
            MAYNSelectionGlassBackground(isSelected: isSelected, isHovering: isHovering, shape: shape)
        }
    }

    /// Keyboard-focus inversion (sidebar, command palette rows).
    func maynInversionSelectionBackground(
        isSelected: Bool,
        isHovering: Bool = false,
        shape: MAYNSelectionShape
    ) -> some View {
        background {
            MAYNSelectionInversionBackground(isSelected: isSelected, isHovering: isHovering, shape: shape)
        }
    }
}

// MARK: - Inversion selection (keyboard focus)

/// Foreground for inversion-selected rows — crisp text on solid fill.
enum MAYNSelectionInversionLabelStyle {
    static func foreground(isSelected: Bool, isDisabled: Bool = false, scheme: ColorScheme) -> Color {
        if isDisabled { return MAYNTheme.textDisabled(scheme) }
        return isSelected ? MAYNTheme.selectionInversionForeground(scheme) : MAYNTheme.textSecondary(scheme)
    }

    static func subtitle(isSelected: Bool, scheme: ColorScheme) -> Color {
        isSelected ? MAYNTheme.selectionInversionSubtitle(scheme) : MAYNTheme.textTertiary(scheme)
    }

    static func weight(isSelected: Bool) -> Font.Weight {
        isSelected ? .semibold : .regular
    }
}

struct MAYNSelectionInversionBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool
    let isHovering: Bool
    let shape: MAYNSelectionShape

    var body: some View {
        Group {
            if isSelected {
                selectedBackground
            } else if isHovering {
                hoverBackground
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var selectedBackground: some View {
        switch shape {
        case .capsule:
            Capsule().fill(MAYNTheme.selectionInversionGradient(colorScheme))
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(MAYNTheme.selectionInversionGradient(colorScheme))
        }
    }

    @ViewBuilder
    private var hoverBackground: some View {
        switch shape {
        case .capsule:
            Capsule().fill(MAYNTheme.hover)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(MAYNTheme.hover)
        }
    }
}
