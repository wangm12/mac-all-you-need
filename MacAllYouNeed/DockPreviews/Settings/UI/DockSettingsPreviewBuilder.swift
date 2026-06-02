import AppKit
import SwiftUI

struct DockSettingsPreviewSnapshot {
    let appName: String
    let showAppHeader: Bool
    let panelOpacity: Double
    let appearance: DockPreviewAppearanceContext
    let backgroundStyle: DockBackgroundStyleFull
    let windows: [DockSettingsMockWindow]
}

enum DockSettingsPreviewBuilder {
    static func signature(hub: DockHubSettings, context: DockSettingsMockPreviewContext) -> String {
        let appearance = hub.appearance
        let options = hub.previews.appearanceOptions
        return [
            context.presentationMode.rawValue,
            appearance.appAppearanceMode.rawValue,
            appearance.backgroundStyle.rawValue,
            appearance.backgroundMaterial.rawValue,
            appearance.useOpaqueBackground.description,
            String(appearance.glassOpacity),
            String(appearance.backgroundTintOpacity),
            String(appearance.backgroundBorderOpacity),
            String(appearance.backgroundBorderWidth),
            appearance.hoverHighlightColorHex ?? "",
            String(appearance.dockPreviewBackgroundOpacity),
            String(appearance.previewWidth),
            String(appearance.previewHeight),
            String(appearance.showWindowTitle),
            String(appearance.uniformCardRadius),
            String(appearance.globalPaddingMultiplier),
            String(appearance.hideHoverContainerBackground),
            String(hub.previews.showThumbnails),
            String(hub.advanced.disableImagePreview),
            String(hub.previews.showAppNameInHeader),
            String(hub.switcher.showAppHeader),
            options.previewHoverAction.rawValue,
            String(hub.previews.enableFullSizeHoverPreview),
        ].joined(separator: "|")
    }

    static func preferredColorScheme(for mode: DockAppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func snapshot(hub: DockHubSettings, context: DockSettingsMockPreviewContext) -> DockSettingsPreviewSnapshot {
        let synced = DockHubSettingsStore.syncedForPreview(hub)
        let previews = synced.previews
        let appearanceSettings = synced.appearance
        let resolved = DockPreviewAppearanceContext.resolve(
            mode: context.presentationMode,
            settings: previews,
            hubAppearance: appearanceSettings,
            switcherShowAppHeader: hub.switcher.showAppHeader
        )
        let appName: String = switch context {
        case .dock: "Preview"
        case .windowSwitcher: "All windows"
        case .cmdTab: "Safari"
        }
        let showHeader: Bool = switch context {
        case .windowSwitcher: hub.switcher.showAppHeader
        case .dock, .cmdTab: resolved.showAppHeader
        }
        return DockSettingsPreviewSnapshot(
            appName: appName,
            showAppHeader: showHeader,
            panelOpacity: previews.hideHoverContainerBackground ? 0 : previews.panelBackgroundOpacity,
            appearance: resolved,
            backgroundStyle: appearanceSettings.backgroundStyle,
            windows: DockSettingsMockWindow.samples(for: context, tint: appearanceSettings.backgroundStyle)
        )
    }

    @MainActor
    static func configure(state: DockPreviewStateCoordinator, hub: DockHubSettings, context: DockSettingsMockPreviewContext) {
        let snap = snapshot(hub: hub, context: context)
        let synced = DockHubSettingsStore.syncedForPreview(hub)

        state.mode = context.presentationMode
        state.settings = synced.previews
        state.presentationMode = hub.advanced.disableImagePreview || !DockPreviewPermissionGate.screenRecordingGranted()
            ? .titlesOnly
            : .fullPreview
        state.enableLivePreview = false
        state.appName = snap.appName
        state.appIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Preview.app")
        state.dockEdge = .bottom
        state.anchorRect = CGRect(x: 400, y: 100, width: 1, height: 1)
        state.appearance = snap.appearance
        state.windows = mockEntries(for: snap)
        state.selectedIndex = 0
        state.shouldScrollToIndex = false
        state.recomputeAndPublishDimensions()
    }

    private static func mockEntries(for snap: DockSettingsPreviewSnapshot) -> [DockPreviewWindowEntry] {
        snap.windows.enumerated().map { index, window in
            DockPreviewWindowEntry(
                id: CGWindowID(index + 1),
                pid: 1,
                title: window.title,
                frame: CGRect(x: 0, y: 0, width: 320, height: 200),
                thumbnail: placeholderThumbnail(label: window.thumbnailLabel, tint: window.tint),
                isMinimized: false,
                isOnScreen: true
            )
        }
    }

    private static func placeholderThumbnail(label: String, tint: DockBackgroundStyleFull) -> NSImage {
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()

        let base: NSColor = switch tint {
        case .liquidGlass: NSColor.systemTeal.withAlphaComponent(0.25)
        case .frostedMaterial: NSColor.systemIndigo.withAlphaComponent(0.18)
        case .clear: NSColor.quaternaryLabelColor
        }
        base.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let str = NSString(string: label)
        let textSize = str.size(withAttributes: attrs)
        str.draw(
            at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
            withAttributes: attrs
        )
        image.unlockFocus()
        return image
    }
}

private extension DockPreviewPresentationMode {
    var rawValue: String {
        switch self {
        case .dockHover: "dockHover"
        case .windowSwitcher: "windowSwitcher"
        case .cmdTab: "cmdTab"
        }
    }
}
