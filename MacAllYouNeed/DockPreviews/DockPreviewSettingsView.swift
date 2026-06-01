import SwiftUI

struct DockPreviewSettingsView: View {
    var onSettingsChanged: (() -> Void)?

    var body: some View {
        MAYNSettingsPage(
            title: "Dock Previews",
            subtitle: "Hover an app's Dock icon to see thumbnails of its windows. Click a thumbnail to raise that window."
        ) {
            DockPreviewSettingsSections(onSettingsChanged: onSettingsChanged)
        }
    }
}

struct DockPreviewSettingsSections: View {
    var onSettingsChanged: (() -> Void)?
    @State private var settings = DockPreviewSettingsStore.load()
    @State private var worklogLineCount = 0

    var body: some View {
        Group {
            DockHubSettingsSections(onSettingsChanged: onSettingsChanged)
            previewsSection
            livePreviewSection
            windowsSection
            placementSection
            captureSection
            folderSection
            appearanceSection
            gesturesSection
            diagnosticsSection
        }
        .onAppear {
            settings = DockPreviewSettingsStore.load()
            refreshWorklogLineCount()
        }
    }

    private func persist() {
        DockPreviewSettingsStore.save(settings)
        onSettingsChanged?()
    }

    private var previewsSection: some View {
        MAYNSection(title: "Previews") {
            MAYNSettingsRow(
                title: "Show window thumbnails",
                subtitle: "Requires Screen Recording; falls back to titles-only when denied."
            ) {
                Toggle("", isOn: binding(\.showThumbnails)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hover delay", subtitle: "Time before the preview panel appears.") {
                MAYNNumericStepper(
                    text: "Hover delay",
                    value: intBinding(\.hoverDelayMS),
                    range: 0 ... 2000,
                    step: 50,
                    presets: [0, 250, 500, 1000],
                    suffix: "ms"
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Fade out duration", subtitle: "Panel dismiss animation length.") {
                MAYNNumericStepper(
                    text: "Fade out",
                    value: intBinding(\.fadeOutDurationMS),
                    range: 0 ... 2000,
                    step: 50,
                    presets: [200, 400, 800],
                    suffix: "ms"
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dismiss inactivity", subtitle: "Delay after leaving the Dock icon.") {
                MAYNNumericStepper(
                    text: "Inactivity",
                    value: intBinding(\.dismissInactivityMS),
                    range: 0 ... 1000,
                    step: 50,
                    presets: [100, 200, 400],
                    suffix: "ms"
                )
            }
        }
    }

    private var livePreviewSection: some View {
        MAYNSection(
            title: "Live preview",
            subtitle: DockPreviewPermissionGate.screenRecordingGranted()
                ? nil
                : "Requires Screen Recording permission."
        ) {
            MAYNSettingsRow(title: "Enable live preview", subtitle: "Stream low-frame-rate video instead of static thumbnails.") {
                Toggle("", isOn: binding(\.enableLivePreview))
                    .labelsHidden()
                    .disabled(!DockPreviewPermissionGate.screenRecordingGranted())
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Quality", subtitle: "Live stream resolution preset.") {
                MAYNDropdown(selection: binding(\.livePreviewQuality), options: DockPreviewLiveQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Frame rate", subtitle: "Maximum live preview frames per second.") {
                MAYNDropdown(selection: binding(\.livePreviewFrameRate), options: DockPreviewLiveFrameRate.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Stream keep-alive", subtitle: "Seconds to keep live streams running after the panel closes (0 = stop immediately).") {
                MAYNNumericStepper(
                    text: "Keep-alive",
                    value: intBinding(\.liveStreamKeepAliveSec),
                    range: 0 ... 30,
                    step: 1,
                    presets: [0, 3, 5, 10],
                    suffix: "sec"
                )
            }
        }
    }

    private var windowsSection: some View {
        MAYNSection(title: "Windows shown") {
            toggleRow("Current Space only", "Only windows on the active desktop Space.", \.currentSpaceOnly)
            MAYNDivider()
            toggleRow("Current monitor only", "Only windows on the display with the hovered Dock icon.", \.currentMonitorOnly)
            MAYNDivider()
            toggleRow("Include hidden/minimized", "Show minimized windows in the strip.", \.includeHiddenMinimized)
            MAYNDivider()
            toggleRow("Show windowless apps", "Show a placeholder when an app has no windows.", \.showWindowlessApps)
            MAYNDivider()
            toggleRow("Group app instances", "Combine windows from duplicate Dock icons.", \.groupAppInstances)
            MAYNDivider()
            toggleRow("Ignore single-window apps", "Skip previews for apps with only one window.", \.ignoreSingleWindowApps)
            MAYNDivider()
            MAYNSettingsRow(title: "Sort order", subtitle: "Order of window cards in the panel.") {
                MAYNDropdown(selection: binding(\.sortOrder), options: DockPreviewSortOrder.allCases) { $0.displayName }
            }
        }
    }

    private var placementSection: some View {
        MAYNSection(title: "Placement") {
            toggleRow("Anchor to Dock icon", "Position the panel beside the hovered icon.", \.anchorToDockIcon)
            MAYNDivider()
            MAYNSettingsRow(title: "Buffer from Dock", subtitle: "Pixel offset from the Dock edge (negative moves closer).") {
                MAYNNumericStepper(
                    text: "Buffer",
                    value: intBinding(\.bufferFromDock),
                    range: -100 ... 100,
                    step: 5,
                    presets: [-40, -20, 0, 20],
                    suffix: "px"
                )
            }
            MAYNDivider()
            toggleRow("Prevent Dock auto-hide", "Keep the Dock visible while a preview is open.", \.preventDockAutoHideWhileOpen)
            MAYNDivider()
            toggleRow("Skip delay when switching apps", "No hover delay when moving between icons with the panel open.", \.skipDelayWhenPanelVisible)
            MAYNDivider()
            toggleRow("Delay only on first open", "Apply hover delay only when opening the first preview.", \.useDelayOnlyForInitialOpen)
            MAYNDivider()
            toggleRow("Block re-entry during fade", "Ignore mouse re-entry while the panel is fading out.", \.preventPreviewReentryDuringFadeOut)
            MAYNDivider()
            toggleRow("Keep preview when app quits", "Leave the panel visible if the hovered app terminates.", \.keepPreviewOnAppQuit)
        }
    }

    private var captureSection: some View {
        MAYNSection(title: "Capture") {
            MAYNSettingsRow(title: "Thumbnail cache lifespan", subtitle: "Reuse captured thumbnails within this window.") {
                MAYNNumericStepper(
                    text: "Cache",
                    value: intBinding(\.thumbnailCacheLifespanSec),
                    range: 5 ... 120,
                    step: 5,
                    presets: [10, 30, 60],
                    suffix: "sec"
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Thumbnail scale", subtitle: "Capture resolution multiplier (1×–3×).") {
                MAYNNumericStepper(
                    text: "Scale",
                    value: thumbnailScaleIntBinding,
                    range: 1 ... 3,
                    step: 1,
                    presets: [1, 2, 3],
                    suffix: "×"
                )
            }
        }
    }

    private var folderSection: some View {
        MAYNSection(title: "Folder dock items") {
            toggleRow("Enable folder widget", "Show folder contents when hovering a directory in the Dock.", \.enableFolderWidget)
            MAYNDivider()
            toggleRow("Show hidden files", "Include dotfiles in folder widgets.", \.folderShowHiddenFiles)
        }
    }

    private var appearanceSection: some View {
        MAYNSection(title: "Appearance") {
            MAYNSettingsRow(title: "Card width", subtitle: "Preview thumbnail width in points.") {
                MAYNNumericStepper(text: "Width", value: intBinding(\.previewCardWidth), range: 120 ... 480, step: 10, presets: [180, 240, 320], suffix: "px")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Card height", subtitle: "Preview thumbnail height in points.") {
                MAYNNumericStepper(text: "Height", value: intBinding(\.previewCardHeight), range: 80 ... 360, step: 10, presets: [120, 150, 200], suffix: "px")
            }
            MAYNDivider()
            toggleRow("Show window titles", "Titles under each preview card.", \.showWindowTitle)
            MAYNDivider()
            toggleRow("Show app name", "App header above the window strip.", \.showAppNameInHeader)
            MAYNDivider()
            toggleRow("Traffic light buttons", "Close, minimize, and zoom on each card.", \.showTrafficLightButtons)
            MAYNDivider()
            MAYNSettingsRow(title: "Compact list threshold", subtitle: "Switch to a text list when window count reaches this number (0 = off).") {
                MAYNNumericStepper(text: "Threshold", value: intBinding(\.compactModeThreshold), range: 0 ... 30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
        }
    }

    private var gesturesSection: some View {
        DockGesturesSettingsSection()
    }

    private var diagnosticsSection: some View {
        MAYNSection(title: "Diagnostics") {
            toggleRow(
                "Worklog",
                "Append hover, show, and dismiss events to App Group worklogs/dock-previews/. Attach when reporting bugs.",
                \.enableWorklog
            )
            MAYNDivider()
            MAYNSettingsRow(
                title: "Reveal worklog",
                subtitle: worklogSubtitle
            ) {
                HStack(spacing: 8) {
                    MAYNButton("Reveal") { DockPreviewWorklog.revealInFinder() }
                    MAYNButton("Clear", role: .destructive) {
                        DockPreviewWorklog.clear()
                        refreshWorklogLineCount()
                    }
                }
            }
        }
    }

    private var worklogSubtitle: String {
        if worklogLineCount == 0 {
            return "No entries yet today. Enable the worklog, reproduce the issue, then reveal or export diagnostics."
        }
        return "\(worklogLineCount) lines in today's worklog."
    }

    private func refreshWorklogLineCount() {
        Task {
            let count = await DockPreviewWorklog.fetchLineCount()
            worklogLineCount = count
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ keyPath: WritableKeyPath<DockPreviewSettings, Bool>) -> some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: binding(keyPath)).labelsHidden()
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DockPreviewSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; persist() }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<DockPreviewSettings, Int>) -> Binding<Int> {
        binding(keyPath)
    }

    private var thumbnailScaleIntBinding: Binding<Int> {
        Binding(
            get: { Int(settings.thumbnailScale.rounded()) },
            set: {
                settings.thumbnailScale = Double($0)
                persist()
            }
        )
    }
}
