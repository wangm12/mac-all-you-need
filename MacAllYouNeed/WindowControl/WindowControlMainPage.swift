import Core
import SwiftUI

struct WindowLayoutsMainPage: View {
    let controller: AppController
    @State private var settings = WindowControlSettingsStore.load()
    @State private var hotkeyMap = HotkeyMapStore.defaultMap

    var body: some View {
        WindowControlFeaturePageShell(
            title: "Window Layouts",
            subtitle: "Arrange, snap, and restore windows.",
            statusText: settings.enabled ? "On" : "Off",
            statusKind: settings.enabled ? .success : .neutral
        ) {
            FunctionPageScrollContent {
                WindowControlSettingsView(
                    controller: controller,
                    settings: $settings,
                    hotkeyMap: $hotkeyMap,
                    scope: .layouts
                )
            }
        }
        .onAppear(perform: reloadState)
    }

    private func reloadState() {
        settings = WindowControlSettingsStore.load()
        hotkeyMap = HotkeyMapStore.load()
    }
}

struct GrabAnywhereMainPage: View {
    let controller: AppController
    @State private var settings = WindowControlSettingsStore.load()
    @State private var hotkeyMap = HotkeyMapStore.defaultMap

    private var isEnabled: Bool {
        settings.enabled && settings.dragAnywhereEnabled
    }

    var body: some View {
        WindowControlFeaturePageShell(
            title: "Window Grab",
            subtitle: "Hold a modifier and drag windows from any visible area.",
            statusText: isEnabled ? "On" : "Off",
            statusKind: isEnabled ? .success : .neutral
        ) {
            FunctionPageScrollContent {
                WindowControlSettingsView(
                    controller: controller,
                    settings: $settings,
                    hotkeyMap: $hotkeyMap,
                    scope: .grabAnywhere
                )
            }
        }
        .onAppear(perform: reloadState)
    }

    private func reloadState() {
        settings = WindowControlSettingsStore.load()
        hotkeyMap = HotkeyMapStore.load()
    }
}

private struct WindowControlFeaturePageShell<Content: View>: View {
    let title: String
    let subtitle: String
    let statusText: String
    let statusKind: StatusPill.Kind
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StatusPill(text: statusText, kind: statusKind)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
                .overlay(MAYNTheme.divider)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MAYNTheme.window)
    }
}

enum WindowControlActionPresentation {
    static func editRoute(for action: HotkeyAction) -> MainAppDestination {
        .windowLayouts
    }
}
