import AppKit
import SwiftUI

struct DockSettingsTabCustomizations: View {
    var onSettingsChanged: (() -> Void)?
    @State private var hub = DockHubSettingsStore.load()
    @State private var newWindowFilter = ""
    @State private var showGlassTuning = false

    var body: some View {
        Group {
            generalAppearanceSection
            DockSettingsMockPreview(hub: hub, context: .dock)
            DockAdvancedSettingsDisclosure {
                appearanceAdvancedSection
                dockPreviewAppearanceSection
                compactModeSection
                dockScrollGestureSection
                titleBarScrollSection
                dockPreviewGesturesSection
                switcherGesturesSection
                gestureSensitivitySection
                mouseActionsSection
                cmdKeyShortcutsSection
                widgetsSection
                activeIndicatorSection
                filtersSection
                advancedSection
            }
        }
        .onAppear { hub = DockHubSettingsStore.load() }
    }

    private func persist() {
        DockHubSettingsStore.save(hub)
        onSettingsChanged?()
    }

    // MARK: General appearance

    private var generalAppearanceSection: some View {
        MAYNSection(title: "Look & feel") {
            MAYNSettingsRow(title: "Theme", subtitle: "Light/dark mode for the Dock preview panel.") {
                MAYNDropdown(selection: binding(\.appearance.appAppearanceMode), options: DockAppearanceMode.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Background style", subtitle: "Visual material for the preview panel background.") {
                MAYNDropdown(selection: binding(\.appearance.backgroundStyle), options: DockBackgroundStyleFull.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Use opaque background", subtitle: "Show an opaque background instead of translucent.") {
                Toggle("", isOn: boolBinding(\.appearance.useOpaqueBackground)).labelsHidden()
            }
        }
    }

    private var appearanceAdvancedSection: some View {
        MAYNSection(title: "Appearance") {
            if hub.appearance.backgroundStyle == .frostedMaterial {
                MAYNSettingsRow(title: "Material thickness", subtitle: "Frosted glass material variant.") {
                    MAYNDropdown(selection: binding(\.appearance.backgroundMaterial), options: DockBackgroundMaterialFull.allCases) { $0.displayName }
                }
                MAYNDivider()
            }
            if hub.appearance.backgroundStyle == .liquidGlass {
                MAYNSettingsRow(title: "Glass opacity", subtitle: "Opacity of the liquid glass background.") {
                    MAYNNumericStepper(text: "Opacity", value: doublePercentBinding(\.appearance.glassOpacity), range: 0...100, step: 5, presets: [50, 75, 90, 100], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Glass blur radius", subtitle: "Blur intensity of the liquid glass effect.") {
                    MAYNNumericStepper(text: "Blur", value: doubleIntBinding(\.appearance.glassBlurRadius), range: 0...80, step: 5, presets: [0, 20, 40, 60], suffix: "pt")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Glass saturation", subtitle: "Color saturation of the liquid glass effect.") {
                    MAYNNumericStepper(text: "Saturation", value: doublePercentBinding(\.appearance.glassSaturation), range: 0...200, step: 5, presets: [80, 100, 120], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Tint intensity", subtitle: "Intensity of the glass tint color.") {
                    MAYNNumericStepper(text: "Tint", value: doublePercentBinding(\.appearance.backgroundTintOpacity), range: 0...100, step: 5, presets: [0, 20, 40], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Border opacity", subtitle: "Opacity of the glass border.") {
                    MAYNNumericStepper(text: "Border", value: doublePercentBinding(\.appearance.backgroundBorderOpacity), range: 0...100, step: 5, presets: [0, 15, 30], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Border width", subtitle: "Width of the glass border line.") {
                    MAYNNumericStepper(text: "Width", value: doubleIntBinding(\.appearance.backgroundBorderWidth), range: 0...4, step: 1, presets: [0, 1, 2], suffix: "pt")
                }
                MAYNDivider()
            }
            MAYNSettingsRow(title: "Spacing scale", subtitle: "Padding multiplier for all chrome elements (0.5× – 2.0×).") {
                MAYNNumericStepper(text: "Scale", value: doublePercentBinding(\.appearance.globalPaddingMultiplier), range: 50...200, step: 10, presets: [50, 100, 150, 200], suffix: "%")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Unselected opacity", subtitle: "Opacity of non-focused window cards.") {
                MAYNNumericStepper(text: "Opacity", value: doublePercentBinding(\.appearance.unselectedContentOpacity), range: 0...100, step: 5, presets: [50, 75, 100], suffix: "%")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Rounded corners", subtitle: "Use rounded corners on preview cards.") {
                Toggle("", isOn: boolBinding(\.appearance.uniformCardRadius)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Long title overflow", subtitle: "How to handle window titles that don't fit.") {
                MAYNDropdown(selection: binding(\.appearance.titleOverflowStyle), options: DockTitleOverflowStyle.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Distinguish minimized/hidden", subtitle: "Show badge overlays for minimized and hidden windows.") {
                Toggle("", isOn: boolBinding(\.appearance.showMinimizedHiddenLabels)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show quit button for windowless apps", subtitle: "Show a quit button for apps that have no open windows.") {
                Toggle("", isOn: boolBinding(\.appearance.showWindowlessAppQuitButton)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide preview card background", subtitle: "Make preview card backgrounds transparent.") {
                Toggle("", isOn: boolBinding(\.appearance.hidePreviewCardBackground)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide container background", subtitle: "Make the hover container background transparent.") {
                Toggle("", isOn: boolBinding(\.appearance.hideHoverContainerBackground)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide widget container background", subtitle: "Make the widget container background transparent.") {
                Toggle("", isOn: boolBinding(\.appearance.hideWidgetContainerBackground)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show active window border", subtitle: "Highlight the currently active window with a colored border.") {
                Toggle("", isOn: boolBinding(\.appearance.showActiveWindowBorder)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable animations", subtitle: "Animate preview panel open/close and selection changes.") {
                Toggle("", isOn: boolBinding(\.appearance.showAnimations)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Lock aspect ratio (16:10)", subtitle: "Keep the preview width-to-height ratio locked.") {
                Toggle("", isOn: boolBinding(\.appearance.lockAspectRatio)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dynamic image sizing", subtitle: "Resize preview cards to fit available space.") {
                Toggle("", isOn: boolBinding(\.appearance.allowDynamicImageSizing)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Preview width", subtitle: "Width of each preview card in points.") {
                MAYNNumericStepper(text: "Width", value: intBinding(\.appearance.previewWidth), range: 100...600, step: 10, presets: [180, 240, 320, 480], suffix: "px")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Preview height", subtitle: "Height of each preview card in points.") {
                MAYNNumericStepper(text: "Height", value: intBinding(\.appearance.previewHeight), range: 60...400, step: 10, presets: [120, 150, 200, 280], suffix: "px")
                    .disabled(hub.appearance.lockAspectRatio)
            }
        }
    }

    // MARK: Dock preview appearance

    private var dockPreviewAppearanceSection: some View {
        MAYNSection(title: "Dock preview appearance") {
            MAYNSettingsRow(title: "Show app header", subtitle: "Show the app name and icon above the window strip.") {
                Toggle("", isOn: boolBinding(\.appearance.showAppName)).labelsHidden()
            }
            if hub.appearance.showAppName {
                MAYNDivider()
                MAYNSettingsRow(title: "App header style", subtitle: "Visual style of the app header.") {
                    MAYNDropdown(selection: binding(\.appearance.appNameStyle), options: DockAppNameStyle.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Show app icon only", subtitle: "Show only the app icon in the header, without the name.") {
                    Toggle("", isOn: boolBinding(\.appearance.showAppIconOnly)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Control position", subtitle: "Position of title and traffic light buttons on cards.") {
                MAYNDropdown(selection: binding(\.appearance.controlPosition), options: DockPreviewControlPosition.allCases) { positionLabel($0) }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show window title", subtitle: "Display the window name on each card.") {
                Toggle("", isOn: boolBinding(\.appearance.showWindowTitle)).labelsHidden()
            }
            if hub.appearance.showWindowTitle {
                MAYNDivider()
                MAYNSettingsRow(title: "Title visibility", subtitle: "When to show the window title.") {
                    MAYNDropdown(selection: binding(\.appearance.windowTitleVisibility), options: DockWindowTitleVisibilityMode.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title display context", subtitle: "Which features show the window title.") {
                    MAYNDropdown(selection: binding(\.appearance.windowTitleDisplayCondition), options: DockWindowTitleDisplayCondition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title font size", subtitle: "Font size for window titles.") {
                    MAYNDropdown(selection: binding(\.appearance.windowTitleFontSize), options: DockWindowTitleFontSize.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title position", subtitle: "Where to place the window title.") {
                    MAYNDropdown(selection: binding(\.appearance.windowTitlePosition), options: DockWindowTitlePosition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling on titles", subtitle: "Remove Dock-style glow from window titles.") {
                    Toggle("", isOn: boolBinding(\.appearance.disableDockStyleTitles)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Traffic light visibility", subtitle: "When close/minimize/fullscreen buttons appear.") {
                MAYNDropdown(selection: binding(\.appearance.trafficLightVisibility), options: DockTrafficLightVisibilityMode.allCases) { $0.displayName }
            }
            if hub.appearance.trafficLightVisibility != .never {
                MAYNDivider()
                MAYNSettingsRow(title: "Traffic light position", subtitle: "Where traffic light buttons appear on each card.") {
                    MAYNDropdown(selection: binding(\.appearance.trafficLightPosition), options: DockTrafficLightPosition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Close", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.close)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Minimize", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.minimize)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Fullscreen", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.toggleFullScreen)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Quit", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.quit)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Monochrome style", subtitle: "Single-color traffic light buttons.") {
                    Toggle("", isOn: boolBinding(\.appearance.useMonochromeTrafficLights)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Button scale", subtitle: "Size multiplier for traffic light buttons.") {
                    MAYNNumericStepper(text: "Scale", value: doublePercentBinding(\.appearance.trafficLightButtonScale), range: 50...200, step: 10, presets: [75, 100, 125, 150], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling", subtitle: "Remove Dock-style glow from traffic light buttons.") {
                    Toggle("", isOn: boolBinding(\.appearance.disableDockStyleTrafficLights)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show mass action buttons", subtitle: "Show Close All and Minimize All buttons in the header.") {
                Toggle("", isOn: boolBinding(\.appearance.showMassActionButtons)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Embed controls in frames", subtitle: "Show controls inside preview frames instead of outside.") {
                Toggle("", isOn: boolBinding(\.appearance.useEmbeddedDockPreviewElements)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Max rows (bottom dock)", subtitle: "Maximum preview rows for bottom-positioned Dock.") {
                MAYNNumericStepper(text: "Rows", value: intBinding(\.appearance.previewMaxRows), range: 1...8, step: 1, presets: [1, 2, 3, 4, 6], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Max columns (side dock)", subtitle: "Maximum preview columns for side-positioned Dock.") {
                MAYNNumericStepper(text: "Cols", value: intBinding(\.appearance.previewMaxColumns), range: 1...8, step: 1, presets: [1, 2, 4, 6, 8], suffix: "")
            }
        }
    }

    // MARK: Compact mode

    private var compactModeSection: some View {
        MAYNSection(title: "Compact mode") {
            MAYNSettingsRow(title: "Always use compact mode", subtitle: "Show text list instead of thumbnails for all previews.") {
                Toggle("", isOn: boolBinding(\.appearance.disableImagePreview)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dock preview threshold", subtitle: "Switch to compact list when window count reaches this (0 = off).") {
                MAYNNumericStepper(text: "Threshold", value: intBinding(\.appearance.dockPreviewCompactThreshold), range: 0...30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Window switcher threshold", subtitle: "Compact threshold for the window switcher.") {
                MAYNNumericStepper(text: "Threshold", value: intBinding(\.appearance.windowSwitcherCompactThreshold), range: 0...30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Cmd+Tab threshold", subtitle: "Compact threshold for Cmd+Tab enhancements.") {
                MAYNNumericStepper(text: "Threshold", value: intBinding(\.appearance.cmdTabCompactThreshold), range: 0...30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Item size", subtitle: "Size of items in compact list mode.") {
                MAYNDropdown(selection: binding(\.appearance.compactModeItemSize), options: DockCompactModeItemSize.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Title format", subtitle: "What information to show in compact list rows.") {
                MAYNDropdown(selection: binding(\.appearance.compactModeTitleFormat), options: DockCompactModeTitleFormat.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide traffic lights in compact mode", subtitle: "Hide traffic light buttons when using the compact list.") {
                Toggle("", isOn: boolBinding(\.appearance.compactModeHideTrafficLights)).labelsHidden()
            }
        }
    }

    // MARK: Dock scroll gesture

    private var dockScrollGestureSection: some View {
        MAYNSection(title: "Dock scroll gesture") {
            MAYNSettingsRow(title: "Enable scroll gestures on dock icons", subtitle: "Scroll on a Dock icon to activate, hide, or control apps.") {
                Toggle("", isOn: boolBinding(\.gestures.enableDockScrollGesture)).labelsHidden()
            }
            if hub.gestures.enableDockScrollGesture {
                MAYNDivider()
                MAYNSettingsRow(title: "Scroll behavior", subtitle: "What scrolling on a Dock icon does.") {
                    MAYNDropdown(selection: binding(\.gestures.dockScrollBehavior), options: DockScrollGestureBehavior.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Media app scroll", subtitle: "Scrolling behavior for music / audio apps.") {
                    MAYNDropdown(selection: binding(\.gestures.dockScrollMediaBehavior), options: DockScrollGestureMediaBehavior.allCases) { $0.displayName }
                }
            }
        }
    }

    // MARK: Title bar scroll

    private var titleBarScrollSection: some View {
        MAYNSection(title: "Title bar scroll gesture") {
            MAYNSettingsRow(title: "Enable title bar scroll", subtitle: "Scroll over an active window's title bar to center and resize it.") {
                Toggle("", isOn: boolBinding(\.gestures.enableTitleBarScrollGesture)).labelsHidden()
            }
            if hub.gestures.enableTitleBarScrollGesture {
                MAYNDivider()
                MAYNSettingsRow(title: "Sizing mode", subtitle: "Whether to resize uniformly or width and height separately.") {
                    MAYNDropdown(selection: binding(\.gestures.titleBarSizingMode), options: DockTitleBarSizingMode.allCases) { $0.displayName }
                }
                if hub.gestures.titleBarSizingMode == .uniform {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Centered window size", subtitle: "Scale of the window when centered (0.5–1.0).") {
                        MAYNNumericStepper(text: "Scale", value: doublePercentBinding(\.gestures.titleBarCenteredScale), range: 50...100, step: 5, presets: [60, 70, 80, 100], suffix: "%")
                    }
                } else {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Lock aspect ratio", subtitle: "Keep width and height proportional.") {
                        Toggle("", isOn: boolBinding(\.gestures.titleBarLockAspectRatio)).labelsHidden()
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Centered width scale", subtitle: "Width as fraction of screen width.") {
                        MAYNNumericStepper(text: "Width", value: doublePercentBinding(\.gestures.titleBarCenteredWidthScale), range: 50...100, step: 5, presets: [60, 70, 80], suffix: "%")
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Centered height scale", subtitle: "Height as fraction of screen height.") {
                        MAYNNumericStepper(text: "Height", value: doublePercentBinding(\.gestures.titleBarCenteredHeightScale), range: 50...100, step: 5, presets: [60, 70, 80], suffix: "%")
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Restore window interval", subtitle: "Seconds before the window snaps back to its original size.") {
                    MAYNNumericStepper(text: "Interval", value: doubleIntBinding(\.gestures.titleBarRestoreInterval), range: 0...5, step: 1, presets: [1, 2, 3], suffix: "s")
                }
            }
        }
    }

    // MARK: Dock preview gestures

    private var dockPreviewGesturesSection: some View {
        MAYNSection(title: "Dock preview gestures") {
            MAYNSettingsRow(title: "Enable gestures on dock window previews", subtitle: "Swipe on preview cards to perform window actions.") {
                Toggle("", isOn: boolBinding(\.gestures.enableDockPreviewGestures)).labelsHidden()
            }
            if hub.gestures.enableDockPreviewGestures {
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe towards Dock action", subtitle: "Action when swiping a card toward the Dock.") {
                    MAYNDropdown(selection: binding(\.gestures.swipeTowardsDockAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe away from Dock action", subtitle: "Action when swiping a card away from the Dock.") {
                    MAYNDropdown(selection: binding(\.gestures.swipeAwayFromDockAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Aero shake action", subtitle: "Action when shaking a window with the mouse.") {
                    MAYNDropdown(selection: binding(\.gestures.aeroShakeAction), options: DockAeroShakeAction.allCases) { $0.displayName }
                }
            }
        }
    }

    // MARK: Window switcher gestures

    private var switcherGesturesSection: some View {
        MAYNSection(title: "Window switcher gestures") {
            MAYNSettingsRow(title: "Enable gestures in window switcher", subtitle: "Swipe on preview cards in the switcher to perform actions.") {
                Toggle("", isOn: boolBinding(\.gestures.enableSwitcherGestures)).labelsHidden()
            }
            if hub.gestures.enableSwitcherGestures {
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe up action", subtitle: "Action when swiping a card upward.") {
                    MAYNDropdown(selection: binding(\.gestures.switcherSwipeUpAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe down action", subtitle: "Action when swiping a card downward.") {
                    MAYNDropdown(selection: binding(\.gestures.switcherSwipeDownAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
            }
        }
    }

    // MARK: Gesture sensitivity

    private var gestureSensitivitySection: some View {
        MAYNSection(title: "Gesture sensitivity") {
            MAYNSettingsRow(title: "Swipe threshold", subtitle: "Minimum swipe distance in pixels to trigger a gesture.") {
                MAYNNumericStepper(text: "Threshold", value: doubleIntBinding(\.gestures.gestureSwipeThreshold), range: 20...100, step: 10, presets: [20, 50, 80, 100], suffix: "px")
            }
        }
    }

    // MARK: Mouse actions

    private var mouseActionsSection: some View {
        MAYNSection(title: "Mouse actions") {
            MAYNSettingsRow(title: "Middle click action", subtitle: "Action performed when middle-clicking a window preview.") {
                MAYNDropdown(selection: binding(\.gestures.middleClickAction), options: DockMiddleClickAction.allCases) { $0.displayName }
            }
        }
    }

    // MARK: Cmd+Key shortcuts

    private var cmdKeyShortcutsSection: some View {
        MAYNSection(title: "⌘+Key shortcuts") {
            shortcutRow(keyPath: \.gestures.cmdShortcut1Key, actionKeyPath: \.gestures.cmdShortcut1Action)
            MAYNDivider()
            shortcutRow(keyPath: \.gestures.cmdShortcut2Key, actionKeyPath: \.gestures.cmdShortcut2Action)
            MAYNDivider()
            shortcutRow(keyPath: \.gestures.cmdShortcut3Key, actionKeyPath: \.gestures.cmdShortcut3Action)
        }
    }

    private func shortcutRow(keyPath: WritableKeyPath<DockHubSettings, UInt16>, actionKeyPath: WritableKeyPath<DockHubSettings, DockWindowSwipeAction>) -> some View {
        MAYNSettingsRow(
            title: "⌘ + \(keyName(hub[keyPath: keyPath]))",
            subtitle: nil
        ) {
            MAYNDropdown(selection: binding(actionKeyPath), options: DockWindowSwipeAction.allCases) { $0.displayName }
        }
    }

    private func keyName(_ code: UInt16) -> String {
        switch code {
        case 13: "W"
        case 46: "M"
        case 12: "Q"
        default: "Key \(code)"
        }
    }

    // MARK: Widgets

    private var widgetsSection: some View {
        MAYNSection(title: "Widgets") {
            MAYNSettingsRow(title: "Enable widget controls on Dock hover", subtitle: "Show media, calendar, and folder widgets when hovering Dock items.") {
                Toggle("", isOn: boolBinding(\.widgets.showSpecialAppControls)).labelsHidden()
            }
            if hub.widgets.showSpecialAppControls {
                MAYNDivider()
                MAYNSettingsRow(title: "Media controls", subtitle: "Show playback controls for the active music app.") {
                    Toggle("", isOn: boolBinding(\.widgets.enableMediaWidget)).labelsHidden()
                }
                if hub.widgets.enableMediaWidget {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Media detection mode", subtitle: "Which apps show the media widget.") {
                        MAYNDropdown(selection: binding(\.widgets.mediaDetectionMode), options: DockMediaDetectionMode.allCases) { $0.displayName }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Calendar widget", subtitle: "Show today's calendar events when hovering Calendar.") {
                    Toggle("", isOn: boolBinding(\.widgets.enableCalendarWidget)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Embedded controls alongside previews", subtitle: "Show widget controls within the preview panel instead of full-size.") {
                    Toggle("", isOn: boolBinding(\.widgets.useEmbeddedMediaControls)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Full controls when all windows minimized", subtitle: "Show full-size controls when an app has no visible windows.") {
                    Toggle("", isOn: boolBinding(\.widgets.showBigControlsWhenNoValidWindows))
                        .labelsHidden()
                        .disabled(!hub.widgets.useEmbeddedMediaControls)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Allow pinning controls to screen", subtitle: "Pin widget controls to the screen so they stay visible.") {
                    Toggle("", isOn: boolBinding(\.widgets.enablePinning)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Media widget scroll behavior", subtitle: "What scrolling over the media widget does.") {
                    MAYNDropdown(selection: binding(\.gestures.mediaScrollBehavior), options: DockMediaScrollBehavior.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Media widget scroll direction", subtitle: "Scroll direction for the media widget.") {
                    MAYNDropdown(selection: binding(\.gestures.mediaScrollDirection), options: DockMediaScrollDirection.allCases) { $0.displayName }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable Dock item widgets", subtitle: "Enable special handling for folder, stack, and archive items in the Dock.") {
                Toggle("", isOn: boolBinding(\.widgets.enableDockItemWidgets)).labelsHidden()
            }
            if hub.widgets.enableDockItemWidgets {
                MAYNDivider()
                MAYNSettingsRow(title: "Folder widget", subtitle: "Show folder contents when hovering a folder or stack in the Dock.") {
                    Toggle("", isOn: boolBinding(\.widgets.enableFolderWidget)).labelsHidden()
                }
                if hub.widgets.enableFolderWidget {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Default sort order", subtitle: "How to sort files in folder widgets.") {
                        MAYNDropdown(selection: binding(\.widgets.folderSortOrder), options: DockFolderSortOrder.allCases) { $0.displayName }
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Sort descending by default", subtitle: "Reverse the sort order so newest/largest items appear first.") {
                        Toggle("", isOn: boolBinding(\.widgets.folderSortReversed)).labelsHidden()
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Remember sort per folder", subtitle: "Save the sort order independently for each folder.") {
                        Toggle("", isOn: boolBinding(\.widgets.folderRememberSortPerFolder)).labelsHidden()
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Show hidden files", subtitle: "Include files whose names start with a period.") {
                        Toggle("", isOn: boolBinding(\.widgets.folderShowHiddenFiles)).labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: Active app indicator

    private var activeIndicatorSection: some View {
        MAYNSection(title: "Active app indicator") {
            MAYNSettingsRow(title: "Enable", subtitle: "Show a colored line below the active application's Dock icon.") {
                Toggle("", isOn: boolBinding(\.master.enableActiveAppIndicator)).labelsHidden()
            }
            if hub.master.enableActiveAppIndicator {
                MAYNDivider()
                MAYNSettingsRow(title: "Auto size", subtitle: "Automatically size the indicator to match the Dock icon.") {
                    Toggle("", isOn: boolBinding(\.indicator.autoSize)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Auto length", subtitle: "Automatically set the length of the indicator.") {
                    Toggle("", isOn: boolBinding(\.indicator.autoLength)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Line height", subtitle: "Thickness of the indicator bar.") {
                    MAYNNumericStepper(text: "Height", value: doubleIntBinding(\.indicator.height), range: 1...12, step: 1, presets: [2, 3, 4, 6], suffix: "pt")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Offset from Dock", subtitle: "Distance from the Dock edge to the indicator.") {
                    MAYNNumericStepper(text: "Offset", value: doubleIntBinding(\.indicator.offset), range: 0...20, step: 1, presets: [0, 2, 5, 8], suffix: "pt")
                }
                if !hub.indicator.autoLength {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Length", subtitle: "Width of the indicator bar.") {
                        MAYNNumericStepper(text: "Length", value: doubleIntBinding(\.indicator.length), range: 10...100, step: 5, presets: [20, 40, 60], suffix: "pt")
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Horizontal shift", subtitle: "Shift the indicator left or right.") {
                        MAYNNumericStepper(text: "Shift", value: doubleIntBinding(\.indicator.shift), range: -30...30, step: 2, presets: [-10, 0, 10], suffix: "pt")
                    }
                }
            }
        }
    }

    // MARK: Filters

    private var filtersSection: some View {
        MAYNSection(title: "Filters") {
            MAYNSettingsRow(title: "Sort minimized windows to end", subtitle: "Move minimized and hidden windows to the end of the list.") {
                Toggle("", isOn: boolBinding(\.filters.sortMinimizedToEnd)).labelsHidden()
            }
            if !hub.filters.appNameFilters.isEmpty {
                MAYNDivider()
                MAYNSettingsRow(title: "Excluded apps", subtitle: nil) { EmptyView() }
                ForEach(Array(hub.filters.appNameFilters.enumerated()), id: \.offset) { idx, name in
                    MAYNDivider()
                    MAYNSettingsRow(title: name, subtitle: nil) {
                        MAYNButton("Remove", role: .destructive) {
                            hub.filters.appNameFilters.remove(at: idx)
                            persist()
                        }
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Window title filters", subtitle: "Hide windows whose titles contain these strings.") {
                EmptyView()
            }
            if !hub.filters.windowTitleFilters.isEmpty {
                ForEach(Array(hub.filters.windowTitleFilters.enumerated()), id: \.offset) { idx, filter in
                    MAYNDivider()
                    MAYNSettingsRow(title: filter, subtitle: nil) {
                        MAYNButton("Remove", role: .destructive) {
                            hub.filters.windowTitleFilters.remove(at: idx)
                            persist()
                        }
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Add window title filter", subtitle: "Hide windows whose title contains this text.") {
                HStack(spacing: 8) {
                    MAYNTextField(placeholder: "e.g. — Untitled", text: $newWindowFilter)
                        .frame(width: 160)
                    MAYNButton("Add") {
                        guard !newWindowFilter.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        hub.filters.windowTitleFilters.append(newWindowFilter.trimmingCharacters(in: .whitespaces))
                        newWindowFilter = ""
                        persist()
                    }
                    .disabled(newWindowFilter.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        MAYNSection(title: "Advanced") {
            MAYNSettingsRow(title: "Window processing debounce", subtitle: "Minimum interval between window list updates.") {
                MAYNNumericStepper(text: "Debounce", value: intBinding(\.advanced.windowProcessingDebounceMS), range: 0...2000, step: 50, presets: [100, 200, 300, 500], suffix: "ms")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show preview above app labels", subtitle: "Raise the preview panel above Dock app labels (restarts app).") {
                Toggle("", isOn: boolBinding(\.advanced.raisedWindowLevel)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Prevent dock from hiding during previews", subtitle: "Keep the Dock visible while any preview is open.") {
                Toggle("", isOn: boolBinding(\.previews.preventDockAutoHideWhileOpen)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Debug mode", subtitle: "Enable verbose logging for bug reporting.") {
                Toggle("", isOn: boolBinding(\.advanced.debugMode)).labelsHidden()
            }
        }
    }

    // MARK: Helpers

    private func positionLabel(_ position: DockPreviewControlPosition) -> String {
        position.rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    private func appearanceTrafficLightToggle(_ action: DockPreviewWindowAction) -> Binding<Bool> {
        Binding(
            get: { hub.appearance.enabledTrafficLightButtons.contains(action) },
            set: { enabled in
                if enabled { hub.appearance.enabledTrafficLightButtons.insert(action) }
                else { hub.appearance.enabledTrafficLightButtons.remove(action) }
                persist()
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DockHubSettings, Bool>) -> Binding<Bool> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }

    private func intBinding(_ keyPath: WritableKeyPath<DockHubSettings, Int>) -> Binding<Int> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }

    private func doubleIntBinding(_ keyPath: WritableKeyPath<DockHubSettings, Double>) -> Binding<Int> {
        Binding(
            get: { Int(hub[keyPath: keyPath].rounded()) },
            set: { hub[keyPath: keyPath] = Double($0); persist() }
        )
    }

    private func doublePercentBinding(_ keyPath: WritableKeyPath<DockHubSettings, Double>) -> Binding<Int> {
        Binding(
            get: { Int((hub[keyPath: keyPath] * 100).rounded()) },
            set: { hub[keyPath: keyPath] = Double($0) / 100.0; persist() }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DockHubSettings, T>) -> Binding<T> {
        Binding(get: { hub[keyPath: keyPath] }, set: { hub[keyPath: keyPath] = $0; persist() })
    }
}
