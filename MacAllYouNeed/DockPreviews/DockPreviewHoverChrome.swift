import AppKit
import SwiftUI

// MARK: - Padding (DockDoor `HoverContainerPadding` + `CardRadius`)

enum DockPreviewHoverPadding {
    static let container: CGFloat = 24
    static let dockStyleOuter: CGFloat = 2
    static let scrollOuter: CGFloat = 2
    static let contentInner: CGFloat = 20
    static let itemSpacing: CGFloat = 24

    static func totalPerSide(paddingMultiplier: CGFloat) -> CGFloat {
        container + dockStyleOuter + scrollOuter + (contentInner * paddingMultiplier)
    }
}

enum DockPreviewCardRadius {
    static let base: CGFloat = 20
    static let innerPadding: CGFloat = 6
    static let outerPadding: CGFloat = 20
    static let fallback: CGFloat = 8

    static func outer(paddingMultiplier: CGFloat, uniformCardRadius: Bool) -> CGFloat {
        uniformCardRadius ? base + (innerPadding * paddingMultiplier) : fallback
    }

    static func image(uniformCardRadius: Bool, paddingMultiplier: CGFloat) -> CGFloat {
        let inner = outer(paddingMultiplier: paddingMultiplier, uniformCardRadius: uniformCardRadius)
        return max(fallback, inner - innerPadding)
    }

    static func container(uniformCardRadius: Bool, paddingMultiplier: CGFloat) -> CGFloat {
        outer(paddingMultiplier: paddingMultiplier, uniformCardRadius: uniformCardRadius) + outerPadding
    }
}

// MARK: - Background appearance

struct DockPreviewResolvedBackgroundAppearance: Equatable {
    var style: DockPreviewBackgroundStyle
    var material: DockPreviewBackgroundMaterial
    var borderOpacity: Double
    var borderWidth: CGFloat
    var useOpaqueBackground: Bool
    var highlightColor: Color?

    static func resolve(options: DockPreviewPanelBackgroundOptions) -> DockPreviewResolvedBackgroundAppearance {
        let highlight: Color? = options.highlightColorHex.flatMap { hex in
            guard let ns = NSColor(hexString: hex) else { return nil }
            return Color(nsColor: ns)
        }
        return DockPreviewResolvedBackgroundAppearance(
            style: options.style,
            material: options.material,
            borderOpacity: options.borderOpacity,
            borderWidth: CGFloat(options.borderWidth),
            useOpaqueBackground: options.useOpaqueBackground,
            highlightColor: highlight
        )
    }
}

/// Panel / card blur (DockDoor `BlurView`, GPL-free).
struct DockPreviewBlurView: View {
    let cornerRadius: CGFloat
    let appearance: DockPreviewResolvedBackgroundAppearance

    var body: some View {
        if appearance.useOpaqueBackground {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else if appearance.style == .clear {
            Color.clear
        } else {
            DockPreviewVisualEffectBackground(
                cornerRadius: cornerRadius,
                opacity: 1,
                material: appearance.material.nsMaterial
            )
        }
    }
}

// MARK: - dockStyle modifier

struct DockPreviewDockStyleModifier: ViewModifier {
    let backgroundOpacity: Double
    let appearance: DockPreviewResolvedBackgroundAppearance
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    DockPreviewBlurView(cornerRadius: cornerRadius, appearance: appearance)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(appearance.borderOpacity),
                                    lineWidth: appearance.borderWidth
                                )
                        }
                    if let highlight = appearance.highlightColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        highlight.opacity(0.15),
                                        highlight.opacity(0.05),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(backgroundOpacity)
            }
            .padding(DockPreviewHoverPadding.dockStyleOuter)
    }
}

extension View {
    func dockPreviewDockStyle(
        backgroundOpacity: Double,
        appearance: DockPreviewResolvedBackgroundAppearance,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(DockPreviewDockStyleModifier(
            backgroundOpacity: backgroundOpacity,
            appearance: appearance,
            cornerRadius: cornerRadius
        ))
    }
}

/// Outer shell (DockDoor `BaseHoverContainer`).
struct DockPreviewBaseHoverContainer<Content: View>: View {
    let screen: NSScreen
    let backgroundOpacity: Double
    let background: DockPreviewResolvedBackgroundAppearance
    let paddingMultiplier: CGFloat
    let uniformCardRadius: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .dockPreviewDockStyle(
                backgroundOpacity: backgroundOpacity,
                appearance: background,
                cornerRadius: DockPreviewCardRadius.container(
                    uniformCardRadius: uniformCardRadius,
                    paddingMultiplier: paddingMultiplier
                )
            )
            .padding(DockPreviewHoverPadding.container)
            .frame(
                maxWidth: screen.visibleFrame.width,
                maxHeight: screen.visibleFrame.height,
                alignment: .topLeading
            )
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
