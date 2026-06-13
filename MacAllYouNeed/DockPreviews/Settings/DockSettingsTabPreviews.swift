import SwiftUI

private enum DockHoverDelayPreset: String, CaseIterable, Identifiable {
    case instant
    case normal
    case relaxed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instant: "Instant"
        case .normal: "Normal"
        case .relaxed: "Relaxed"
        }
    }

    var milliseconds: Int {
        switch self {
        case .instant: 0
        case .normal: 200
        case .relaxed: 500
        }
    }

    static func from(milliseconds: Int) -> Self {
        switch milliseconds {
        case 0: .instant
        case ..<350: .normal
        default: .relaxed
        }
    }
}

struct DockSettingsTabPreviews: View {
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?

    private var settings: DockSettingsHubBindings {
        DockSettingsHubBindings(hub: $hub, onSettingsChanged: onSettingsChanged)
    }

    var body: some View {
        Group {
            generalSection
            DockAdvancedSettingsDisclosure {
                fadeTimingSection
                livePreviewAdvancedSection
                captureSection
                windowsSection
                placementSection
                dockInteractionsSection
                advancedBehaviorSection
            }
        }
    }

    // MARK: General

    private var generalSection: some View {
        MAYNSection(title: "Previews") {
            MAYNSettingsRow(title: "Show window thumbnails", subtitle: "Requires Screen Recording; falls back to titles-only when denied.") {
                Toggle("", isOn: settings.bool(\.previews.showThumbnails)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hover delay", subtitle: "Time before the preview panel appears.") {
                MAYNDropdown(
                    selection: Binding(
                        get: { DockHoverDelayPreset.from(milliseconds: hub.previews.hoverDelayMS) },
                        set: { hub.previews.hoverDelayMS = $0.milliseconds; settings.persist() }
                    ),
                    options: DockHoverDelayPreset.allCases
                ) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Enable live preview",
                subtitle: DockPreviewPermissionGate.screenRecordingGranted()
                    ? "Stream low-frame-rate video instead of static thumbnails."
                    : "Requires Screen Recording permission."
            ) {
                Toggle("", isOn: settings.bool(\.previews.enableLivePreview))
                    .labelsHidden()
                    .disabled(!DockPreviewPermissionGate.screenRecordingGranted())
            }
        }
    }

    // MARK: Advanced sections

    private var fadeTimingSection: some View {
        MAYNSection(title: "Timing") {
            MAYNSettingsRow(title: "Fade out duration", subtitle: "Panel dismiss animation length.") {
                MAYNNumericStepper(text: "Fade out", value: settings.int(\.previews.fadeOutDurationMS), range: 0...2000, step: 50, presets: [200, 400, 800], suffix: "ms")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dismiss inactivity", subtitle: "Delay after leaving the Dock icon before hiding.") {
                MAYNNumericStepper(text: "Inactivity", value: settings.int(\.previews.dismissInactivityMS), range: 0...1000, step: 50, presets: [100, 200, 400], suffix: "ms")
            }
        }
    }

    private var livePreviewAdvancedSection: some View {
        MAYNSection(title: "Live preview") {
            MAYNSettingsRow(title: "Dock preview quality", subtitle: "Live stream resolution for dock hover.") {
                MAYNDropdown(selection: settings.value(\.advanced.dockLivePreviewQuality), options: DockLivePreviewQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dock preview frame rate", subtitle: "Maximum frames per second for dock hover.") {
                MAYNDropdown(selection: settings.value(\.advanced.dockLivePreviewFrameRate), options: DockLivePreviewFrameRate.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable for window switcher", subtitle: "Live preview in the Alt+Tab window switcher.") {
                Toggle("", isOn: settings.bool(\.advanced.enableLivePreviewForSwitcher)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Switcher quality", subtitle: "Live stream resolution for window switcher.") {
                MAYNDropdown(selection: settings.value(\.advanced.switcherLivePreviewQuality), options: DockLivePreviewQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Switcher frame rate", subtitle: "Maximum frames per second for window switcher.") {
                MAYNDropdown(selection: settings.value(\.advanced.switcherLivePreviewFrameRate), options: DockLivePreviewFrameRate.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Switcher scope", subtitle: "Which windows get live preview in the switcher.") {
                MAYNDropdown(selection: settings.value(\.advanced.switcherLivePreviewScope), options: DockLivePreviewScope.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Stream keep-alive", subtitle: "Seconds to keep live streams running after the panel closes (0 = stop immediately).") {
                MAYNNumericStepper(text: "Keep-alive", value: settings.int(\.advanced.livePreviewStreamKeepAlive), range: 0...30, step: 1, presets: [0, 3, 5, 10], suffix: "sec")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "HDR live preview", subtitle: "Capture HDR/P3 colors on macOS 15+ (uses more memory).") {
                Toggle("", isOn: settings.bool(\.advanced.enableHDRLivePreview)).labelsHidden()
            }
        }
    }

    private var captureSection: some View {
        MAYNSection(title: "Capture") {
            MAYNSettingsRow(title: "Window image quality", subtitle: "Screenshot capture resolution mode.") {
                MAYNDropdown(selection: settings.value(\.advanced.windowImageCaptureQuality), options: DockWindowImageCaptureQuality.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Window image cache lifespan", subtitle: "Reuse captured thumbnails within this window (DockDoor screen capture cache).") {
                MAYNNumericStepper(
                    text: "Cache",
                    value: settings.roundedInt(from: \.advanced.screenCaptureCacheLifespan),
                    range: 0...60,
                    step: 10,
                    presets: [0, 10, 30, 60],
                    suffix: "sec"
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Thumbnail scale", subtitle: "Capture resolution multiplier (1×–4×).") {
                MAYNNumericStepper(text: "Scale", value: settings.int(\.advanced.windowPreviewImageScale), range: 1...4, step: 1, presets: [1, 2, 3, 4], suffix: "×")
            }
        }
    }

    private var windowsSection: some View {
        MAYNSection(title: "Windows shown") {
            settings.toggleRow("Current Space only", "Only windows on the active desktop Space.", \.previews.currentSpaceOnly)
            MAYNDivider()
            settings.toggleRow("Current monitor only", "Only windows on the display with the hovered Dock icon.", \.previews.currentMonitorOnly)
            MAYNDivider()
            settings.toggleRow("Include hidden/minimized", "Show minimized and hidden windows in the strip.", \.previews.includeHiddenMinimized)
            MAYNDivider()
            settings.toggleRow("Show windowless apps", "Show a placeholder when an app has no windows.", \.previews.showWindowlessApps)
            MAYNDivider()
            settings.toggleRow("Keep preview when app quits", "Leave the panel visible if the hovered app terminates.", \.previews.keepPreviewOnAppQuit)
            MAYNDivider()
            settings.toggleRow("Group app instances", "Combine windows from duplicate Dock icons.", \.previews.groupAppInstances)
            MAYNDivider()
            settings.toggleRow("Ignore single-window apps", "Skip previews for apps with only one window.", \.previews.ignoreSingleWindowApps)
            MAYNDivider()
            MAYNSettingsRow(title: "Sort order", subtitle: "Order of window cards in the panel.") {
                MAYNDropdown(selection: settings.value(\.previews.sortOrder), options: DockPreviewSortOrder.allCases) { $0.displayName }
            }
        }
    }

    private var placementSection: some View {
        MAYNSection(title: "Placement") {
            settings.toggleRow("Anchor to Dock icon", "Position the panel beside the hovered icon.", \.previews.anchorToDockIcon)
            MAYNDivider()
            settings.toggleRow("Overlay Dock tooltip", "Hide the native Dock label while a preview is open.", \.previews.overlayDockTooltip)
            MAYNDivider()
            MAYNSettingsRow(title: "Buffer from Dock", subtitle: "Pixel offset from the Dock edge (negative moves closer).") {
                MAYNNumericStepper(text: "Buffer", value: settings.int(\.previews.bufferFromDock), range: -100...100, step: 5, presets: [-40, -20, 0, 20], suffix: "px")
            }
            MAYNDivider()
            settings.toggleRow("Prevent Dock auto-hide", "Keep the Dock visible while a preview is open.", \.previews.preventDockAutoHideWhileOpen)
            MAYNDivider()
            settings.toggleRow("Skip delay when switching apps", "No hover delay when moving between icons with panel open.", \.previews.skipDelayWhenPanelVisible)
            MAYNDivider()
            settings.toggleRow("Delay only on first open", "Apply hover delay only when opening the first preview.", \.previews.useDelayOnlyForInitialOpen)
            MAYNDivider()
            settings.toggleRow("Block re-entry during fade", "Ignore mouse re-entry while the panel is fading out.", \.previews.preventPreviewReentryDuringFadeOut)
        }
    }

    private var dockInteractionsSection: some View {
        MAYNSection(title: "Dock interactions") {
            MAYNSettingsRow(
                title: "Preview hover action",
                subtitle: "What happens when you hover a window card in dock previews. None keeps windows in place."
            ) {
                MAYNDropdown(
                    selection: Binding(
                        get: { hub.previews.appearanceOptions.previewHoverAction },
                        set: {
                            hub.previews.appearanceOptions.previewHoverAction = $0
                            if $0 != .fullSizePreview {
                                hub.previews.enableFullSizeHoverPreview = false
                            }
                            settings.persist()
                        }
                    ),
                    options: DockPreviewPreviewHoverAction.allCases
                ) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Full-size hover overlay",
                subtitle: "Show a large floating preview when hovering a window card."
            ) {
                Toggle("", isOn: settings.bool(\.previews.enableFullSizeHoverPreview))
                    .labelsHidden()
                    .disabled(hub.previews.appearanceOptions.previewHoverAction != .fullSizePreview)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "CMD + Right-Click to quit", subtitle: "Quickly quit an app by right-clicking its Dock icon while holding ⌘.") {
                Toggle("", isOn: settings.bool(\.interaction.enableCmdRightClickQuit)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Quit app on last window close", subtitle: "Automatically quit the app when you close its last window.") {
                Toggle("", isOn: settings.bool(\.interaction.quitAppOnLastWindowClose)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide all windows on Dock click", subtitle: "Clicking the Dock icon hides all app windows.") {
                Toggle("", isOn: settings.bool(\.interaction.hideAllOnDockClick)).labelsHidden()
            }
            if hub.interaction.hideAllOnDockClick {
                MAYNDivider()
                MAYNSettingsRow(title: "Dock click action", subtitle: "What happens when clicking the Dock icon.") {
                    MAYNDropdown(selection: settings.value(\.interaction.dockClickAction), options: DockClickAction.allCases) { $0.displayName }
                }
                if hub.interaction.dockClickAction == .minimize {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Restore all minimized on click", subtitle: "Restore all minimized windows when clicking the Dock icon again.") {
                        Toggle("", isOn: settings.bool(\.interaction.restoreAllMinimizedOnDockClick)).labelsHidden()
                    }
                }
            }
        }
    }

    private var advancedBehaviorSection: some View {
        MAYNSection(title: "Advanced behavior") {
            MAYNSettingsRow(title: "Open new window for windowless apps", subtitle: "Open a new window when clicking an app with no open windows.") {
                Toggle("", isOn: settings.bool(\.advanced.openNewWindowForWindowlessApps)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show small windows (under 100px)", subtitle: "Include very small windows that are normally hidden.") {
                Toggle("", isOn: settings.bool(\.advanced.disableMinWindowSizeFilter)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Raised window level", subtitle: "Show preview panel above app labels (restarts app).") {
                Toggle("", isOn: settings.bool(\.advanced.raisedWindowLevel)).labelsHidden()
            }
        }
    }
}
