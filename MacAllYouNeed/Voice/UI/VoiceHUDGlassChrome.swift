import AppKit
import SwiftUI

/// Shared Liquid Glass chrome for the voice hub pill and caption chip.
/// macOS 26+: `glassEffect(.regular)` per [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass).
/// macOS 14–25: `NSVisualEffectView` with `.behindWindow` + `thinMaterial` fallback.
enum VoiceHUDGlassChrome {
    /// Floating runtime controls over arbitrary desktops — use `.regular`, not `.clear`.
    static let material: MAYNMaterial = .panel
}

// MARK: - Backdrop (pre-26)

private struct VoiceHUDWindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Surface modifier

private struct VoiceHUDSurfaceModifier: ViewModifier {
    let isGraphite: Bool
    let cornerRadius: CGFloat
    let isCapsule: Bool

    func body(content: Content) -> some View {
        Group {
            if isCapsule {
                content
                    .background {
                        Group {
                            if isGraphite {
                                graphiteFill
                            } else {
                                glassFill
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .clipShape(Capsule())
            } else {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                content
                    .background {
                        Group {
                            if isGraphite {
                                graphiteFill
                            } else {
                                glassFill
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .clipShape(shape)
            }
        }
    }

    @ViewBuilder
    private var graphiteFill: some View {
        if isCapsule {
            Capsule().fill(MiniVoiceHUDPalette.pillGraphite)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(MiniVoiceHUDPalette.pillGraphite)
        }
    }

    @ViewBuilder
    private var glassFill: some View {
        if isCapsule {
            if #available(macOS 26.0, *) {
                ZStack {
                    Capsule().fill(Color.clear)
                        .glassEffect(.regular, in: Capsule())
                    Capsule().stroke(MAYNMaterial.panel.borderColor, lineWidth: 1)
                }
            } else {
                ZStack {
                    VoiceHUDWindowBackdrop()
                    Capsule().stroke(MAYNMaterial.panel.borderColor, lineWidth: 1)
                }
                .clipShape(Capsule())
            }
        } else if #available(macOS 26.0, *) {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.fill(Color.clear)
                    .glassEffect(.regular, in: shape)
                shape.stroke(MAYNMaterial.panel.borderColor, lineWidth: 1)
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                VoiceHUDWindowBackdrop()
                shape.stroke(MAYNMaterial.panel.borderColor, lineWidth: 1)
            }
            .clipShape(shape)
        }
    }
}

extension View {
    /// Voice hub pill — capsule Liquid Glass or legacy graphite.
    func voiceHubPillChrome(isGraphite: Bool) -> some View {
        modifier(
            VoiceHUDSurfaceModifier(
                isGraphite: isGraphite,
                cornerRadius: MiniVoiceHUDLayout.cornerRadius,
                isCapsule: true
            )
        )
    }

    /// Caption chip above the hub pill — matched glass language, rounded rect.
    func voiceHubCaptionChrome(isGraphite: Bool) -> some View {
        modifier(
            VoiceHUDSurfaceModifier(
                isGraphite: isGraphite,
                cornerRadius: MiniVoiceHUDLayout.captionCornerRadius,
                isCapsule: false
            )
        )
    }
}
