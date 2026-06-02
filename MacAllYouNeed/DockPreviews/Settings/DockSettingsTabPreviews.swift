import SwiftUI

struct DockSettingsTabPreviews: View {
    var onSettingsChanged: (() -> Void)?
    @State private var hub = DockHubSettingsStore.load()
    @State private var worklogLineCount = 0

    private var settings: DockPreviewSettings {
        get { hub.previews }
        set { hub.previews = newValue }
    }

    var body: some View {
        Group {
            previewsSection
            livePreviewSection
            captureSection
            windowsSection
            placementSection
            dockInteractionsSection
            advancedBehaviorSection
            diagnosticsSection
        }
        .onAppear {
            hub = DockHubSettingsStore.load()
            refreshWorklogLineCount()
        }
    }

    private func persist() {
        DockHubSettingsStore.save(hub)
        onSettingsChanged?()
    }

    // MARK: Previews

    private var previewsSection: some View {
        MAYNSection(title: "Previews") {
            MAYNSettingsRow(title: "Show window thumbnails", subtitle: "Requires Screen Recording; falls back to titles-only when denied.") {
                Toggle("", isOn: boolBinding(\.previews.showThumbnails)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hover delay", subtitle: "Time before the preview panel appears.") {
                MAYNNumericStepper(text: "Hover delay", value: intBinding(\.previews.hoverDelayMS), range: 0...2000, step: 50, presets: [0, 250, 500, 1000], suffix: "ms")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Fade out duration", subtitle: "Panel dismiss animation length.") {
                MAYNNumericStepper(text: "Fade out", value: intBinding(\.previews.fadeOutDurationMS), range: 0...2000, step: 50, presets: [200, 400, 800], suffix: "ms")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dismiss inactivity", subtitle: "Delay after leaving the Dock icon before hiding.") {
                MAYNNumericStepper(text: "Inactivity", value: intBinding(\.previews.dismissInactivityMS), range: 0...1000, step: 50, presets: [100, 200, 400], suffix: "ms")
            }
        }
    }

    // MARK: Live preview

    private var livePreviewSection: some View {
        MAYNSection(
            title: "Live preview",
            subtitle: DockPreviewPermissionGate.screenRecordingGranted() ? nil : "Requires Screen Recording permission."
        ) {
            MAYNSettingsRow(title: "Enable live preview", subtitle: "Stream low-frame-rate video instead of static thumbnails.") {
                Toggle("", isOn: boolBinding(\.previews.enableLivePreview))
                    .labelsHidden()
                    .disabled(!DockPreviewPermissionGate.screenRecordingGranted())
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dock preview quality", subtitle: "Live stream resolution for dock hover.") {
                MAYNDropdown(selection: binding(\.advanced.dockLivePreviewQuality), options: DockLivePreviewQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dock preview frame rate", subtitle: "Maximum frames per second for dock hover.") {
                MAYNDropdown(selection: binding(\.advanced.dockLivePreviewFrameRate), options: DockLivePreviewFrameRate.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable for window switcher", subtitle: "Live preview in the Alt+Tab window switcher.") {
                Toggle("", isOn: boolBinding(\.advanced.enableLivePreviewForSwitcher)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Switcher quality", subtitle: "Live stream resolution for window switcher.") {
                MAYNDropdown(selection: binding(\.advanced.switcherLivePreviewQuality), options: DockLivePreviewQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Switcher frame rate", subtitle: "Maximum frames per second for window switcher.") {
                MAYNDropdown(selection: binding(\.advanced.switcherLivePreviewFrameRate), options: DockLivePreviewFrameRate.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Switcher scope", subtitle: "Which windows get live preview in the switcher.") {
                MAYNDropdown(selection: binding(\.advanced.switcherLivePreviewScope), options: DockLivePreviewScope.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Stream keep-alive", subtitle: "Seconds to keep live streams running after the panel closes (0 = stop immediately).") {
                MAYNNumericStepper(text: "Keep-alive", value: intBinding(\.advanced.livePreviewStreamKeepAlive), range: 0...30, step: 1, presets: [0, 3, 5, 10], suffix: "sec")
            }
        }
    }

    // MARK: Capture

    private var captureSection: some View {
        MAYNSection(title: "Capture") {
            MAYNSettingsRow(title: "Window image quality", subtitle: "Screenshot capture resolution mode.") {
                MAYNDropdown(selection: binding(\.advanced.windowImageCaptureQuality), options: DockWindowImageCaptureQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Thumbnail cache lifespan", subtitle: "Reuse captured thumbnails within this window.") {
                MAYNNumericStepper(text: "Cache", value: intBinding(\.previews.thumbnailCacheLifespanSec), range: 5...120, step: 5, presets: [10, 30, 60], suffix: "sec")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Thumbnail scale", subtitle: "Capture resolution multiplier (1×–4×).") {
                MAYNNumericStepper(text: "Scale", value: intBinding(\.advanced.windowPreviewImageScale), range: 1...4, step: 1, presets: [1, 2, 3, 4], suffix: "×")
            }
        }
    }

    // MARK: Windows shown

    private var windowsSection: some View {
        MAYNSection(title: "Windows shown") {
            toggleRow("Current Space only", "Only windows on the active desktop Space.", \.previews.currentSpaceOnly)
            MAYNDivider()
            toggleRow("Current monitor only", "Only windows on the display with the hovered Dock icon.", \.previews.currentMonitorOnly)
            MAYNDivider()
            toggleRow("Include hidden/minimized", "Show minimized and hidden windows in the strip.", \.previews.includeHiddenMinimized)
            MAYNDivider()
            toggleRow("Show windowless apps", "Show a placeholder when an app has no windows.", \.previews.showWindowlessApps)
            MAYNDivider()
            toggleRow("Keep preview when app quits", "Leave the panel visible if the hovered app terminates.", \.previews.keepPreviewOnAppQuit)
            MAYNDivider()
            toggleRow("Group app instances", "Combine windows from duplicate Dock icons.", \.previews.groupAppInstances)
            MAYNDivider()
            toggleRow("Ignore single-window apps", "Skip previews for apps with only one window.", \.previews.ignoreSingleWindowApps)
            MAYNDivider()
            MAYNSettingsRow(title: "Sort order", subtitle: "Order of window cards in the panel.") {
                MAYNDropdown(selection: binding(\.previews.sortOrder), options: DockPreviewSortOrder.allCases) { $0.displayName }
            }
        }
    }

    // MARK: Placement

    private var placementSection: some View {
        MAYNSection(title: "Placement") {
            toggleRow("Anchor to Dock icon", "Position the panel beside the hovered icon.", \.previews.anchorToDockIcon)
            MAYNDivider()
            MAYNSettingsRow(title: "Buffer from Dock", subtitle: "Pixel offset from the Dock edge (negative moves closer).") {
                MAYNNumericStepper(text: "Buffer", value: intBinding(\.previews.bufferFromDock), range: -100...100, step: 5, presets: [-40, -20, 0, 20], suffix: "px")
            }
            MAYNDivider()
            toggleRow("Prevent Dock auto-hide", "Keep the Dock visible while a preview is open.", \.previews.preventDockAutoHideWhileOpen)
            MAYNDivider()
            toggleRow("Skip delay when switching apps", "No hover delay when moving between icons with panel open.", \.previews.skipDelayWhenPanelVisible)
            MAYNDivider()
            toggleRow("Delay only on first open", "Apply hover delay only when opening the first preview.", \.previews.useDelayOnlyForInitialOpen)
            MAYNDivider()
            toggleRow("Block re-entry during fade", "Ignore mouse re-entry while the panel is fading out.", \.previews.preventPreviewReentryDuringFadeOut)
        }
    }

    // MARK: Dock interactions

    private var dockInteractionsSection: some View {
        MAYNSection(title: "Dock interactions") {
            MAYNSettingsRow(title: "CMD + Right-Click to quit", subtitle: "Quickly quit an app by right-clicking its Dock icon while holding ⌘.") {
                Toggle("", isOn: boolBinding(\.interaction.enableCmdRightClickQuit)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Quit app on last window close", subtitle: "Automatically quit the app when you close its last window.") {
                Toggle("", isOn: boolBinding(\.interaction.quitAppOnLastWindowClose)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide all windows on Dock click", subtitle: "Clicking the Dock icon hides all app windows.") {
                Toggle("", isOn: boolBinding(\.interaction.hideAllOnDockClick)).labelsHidden()
            }
            if hub.interaction.hideAllOnDockClick {
                MAYNDivider()
                MAYNSettingsRow(title: "Dock click action", subtitle: "What happens when clicking the Dock icon.") {
                    MAYNDropdown(selection: binding(\.interaction.dockClickAction), options: DockClickAction.allCases) { $0.displayName }
                }
                if hub.interaction.dockClickAction == .minimize {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Restore all minimized on click", subtitle: "Restore all minimized windows when clicking the Dock icon again.") {
                        Toggle("", isOn: boolBinding(\.interaction.restoreAllMinimizedOnDockClick)).labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: Advanced behavior

    private var advancedBehaviorSection: some View {
        MAYNSection(title: "Advanced behavior") {
            MAYNSettingsRow(title: "Open new window for windowless apps", subtitle: "Open a new window when clicking an app with no open windows.") {
                Toggle("", isOn: boolBinding(\.advanced.openNewWindowForWindowlessApps)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show small windows (under 100px)", subtitle: "Include very small windows that are normally hidden.") {
                Toggle("", isOn: boolBinding(\.advanced.disableMinWindowSizeFilter)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Raised window level", subtitle: "Show preview panel above app labels (restarts app).") {
                Toggle("", isOn: boolBinding(\.advanced.raisedWindowLevel)).labelsHidden()
            }
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        MAYNSection(title: "Diagnostics") {
            toggleRow("Worklog", "Append hover, show, and dismiss events to worklogs.", \.previews.enableWorklog)
            MAYNDivider()
            MAYNSettingsRow(title: "Reveal worklog", subtitle: worklogSubtitle) {
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
        worklogLineCount == 0
            ? "No entries yet today."
            : "\(worklogLineCount) lines in today's worklog."
    }

    private func refreshWorklogLineCount() {
        Task {
            let count = await DockPreviewWorklog.fetchLineCount()
            worklogLineCount = count
        }
    }

    // MARK: Helpers

    private func toggleRow(_ title: String, _ subtitle: String, _ keyPath: WritableKeyPath<DockHubSettings, Bool>) -> some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: Binding(
                get: { hub[keyPath: keyPath] },
                set: { hub[keyPath: keyPath] = $0; persist() }
            )).labelsHidden()
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DockHubSettings, Bool>) -> Binding<Bool> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }

    private func intBinding(_ keyPath: WritableKeyPath<DockHubSettings, Int>) -> Binding<Int> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DockHubSettings, T>) -> Binding<T> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }
}
