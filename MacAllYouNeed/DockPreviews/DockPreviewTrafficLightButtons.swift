import AppKit
import ApplicationServices
import Foundation
import SwiftUI

/// Dock-style window controls on preview cards (DockDoor `TrafficLightButtons`).
struct DockPreviewTrafficLightButtons: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: DockPreviewWindowEntry
    let appearance: DockPreviewAppearanceContext
    let hoveringOverParentWindow: Bool
    let onClose: () -> Void

    @State private var isHoveringButtons = false

    var body: some View {
        Group {
            if appearance.trafficLightVisibility != .never, !appearance.enabledTrafficLightButtons.isEmpty {
                HStack(spacing: 6 * appearance.trafficLightButtonScale) {
                    ForEach(Array(appearance.enabledTrafficLightButtons).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { action in
                        buttonFor(action: action)
                    }
                }
                .padding(4)
                .opacity(buttonOpacity)
                .if(!appearance.disableDockStyleTrafficLights && buttonOpacity > 0) { view in
                    view.dockPreviewMaterialPill(background: appearance.background)
                }
                .allowsHitTesting(buttonOpacity > 0)
                .onHover { hovering in
                    withAnimation(MAYNMotion.hoverAnimation(reduceMotion: false)) {
                        isHoveringButtons = hovering
                    }
                }
            }
        }
    }

    private var buttonOpacity: Double {
        switch appearance.trafficLightVisibility {
        case .never:
            0
        case .dimmedOnPreviewHover:
            (hoveringOverParentWindow && isHoveringButtons) ? 1 : 0.25
        case .fullOpacityOnPreviewHover:
            hoveringOverParentWindow ? 1 : 0.25
        case .alwaysVisible:
            1
        }
    }

    @ViewBuilder
    private func buttonFor(action: DockPreviewWindowAction) -> some View {
        let monochromeFill = colorScheme == .dark ? Color.gray.opacity(0.925) : Color.white
        let (glyphColor, fillColor) = colors(for: action, monochromeFill: monochromeFill)
        Button {
            perform(action)
        } label: {
            ZStack {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
                Image(systemName: "\(action.symbolName).circle.fill")
            }
            .foregroundStyle(glyphColor, fillColor)
            .font(.headline)
            .scaleEffect(appearance.trafficLightButtonScale)
            .frame(
                width: 17 * appearance.trafficLightButtonScale,
                height: 17 * appearance.trafficLightButtonScale
            )
        }
        .buttonStyle(.plain)
    }

    private func colors(for action: DockPreviewWindowAction, monochromeFill: Color) -> (Color, Color) {
        if appearance.useMonochromeTrafficLights {
            return (.secondary, monochromeFill)
        }
        switch action {
        case .quit: return (Color(red: 0.16, green: 0.004, blue: 0.2), Color.purple)
        case .close: return (Color(red: 0.49, green: 0.024, blue: 0.035), Color.red)
        case .minimize: return (Color(red: 0.59, green: 0.34, blue: 0.07), Color.yellow)
        case .toggleFullScreen: return (Color(red: 0.05, green: 0.40, blue: 0.05), Color.green)
        case .maximize: return (Color(red: 0.04, green: 0.35, blue: 0.29), Color.teal)
        }
    }

    private func perform(_ action: DockPreviewWindowAction) {
        switch action {
        case .quit:
            DockPreviewWindowActions.quitApplication(pid: entry.pid)
        case .close:
            DockPreviewWindowActions.close(entry: entry)
            onClose()
        case .minimize:
            DockPreviewWindowActions.minimize(entry: entry)
        case .toggleFullScreen:
            DockPreviewWindowActions.toggleFullScreen(entry: entry)
        case .maximize:
            DockPreviewWindowActions.zoom(entry: entry)
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition { transform(self) } else { self }
    }
}
