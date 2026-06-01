import SwiftUI

struct DockPreviewTrafficLightButtons: View {
    let entry: DockPreviewWindowEntry
    let appearance: DockPreviewAppearanceContext
    let hovering: Bool
    let onClose: () -> Void

    private var visible: Bool {
        switch appearance.trafficLightVisibility {
        case .never: false
        case .always: true
        case .onHover: hovering
        }
    }

    var body: some View {
        Group {
            if visible {
                HStack(spacing: 6 * appearance.trafficLightButtonScale) {
                    trafficDot(color: appearance.useMonochromeTrafficLights ? .primary.opacity(0.5) : MAYNTheme.danger) {
                        DockPreviewWindowActions.close(entry: entry)
                        onClose()
                    }
                    trafficDot(color: appearance.useMonochromeTrafficLights ? .primary.opacity(0.4) : MAYNTheme.warning) {
                        DockPreviewWindowActions.minimize(entry: entry)
                    }
                    trafficDot(color: appearance.useMonochromeTrafficLights ? .primary.opacity(0.35) : MAYNTheme.success) {
                        DockPreviewWindowActions.zoom(entry: entry)
                    }
                }
                .if(!appearance.disableDockStyleTrafficLights) { view in
                    view.dockPreviewMaterialPill(background: appearance.background)
                }
            }
        }
    }

    private func trafficDot(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 10 * appearance.trafficLightButtonScale, height: 10 * appearance.trafficLightButtonScale)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition { transform(self) } else { self }
    }
}
