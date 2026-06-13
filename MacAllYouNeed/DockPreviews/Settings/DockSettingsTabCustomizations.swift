import AppKit
import SwiftUI

struct DockSettingsTabCustomizations: View {
    @Binding var hub: DockHubSettings
    var onSettingsChanged: (() -> Void)?
    @State private var newWindowFilter = ""
    @State private var newWidgetFilter = ""

    private var settings: DockSettingsHubBindings {
        DockSettingsHubBindings(hub: $hub, onSettingsChanged: onSettingsChanged)
    }

    var body: some View {
        Group {
            generalAppearanceSection
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
    }

    // MARK: General appearance

    private var generalAppearanceSection: some View {
        MAYNSection(title: "Look & feel") {
            MAYNSettingsRow(title: "Theme", subtitle: "Light/dark mode for the Dock preview panel.") {
                MAYNDropdown(selection: settings.value(\.appearance.appAppearanceMode), options: DockAppearanceMode.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Background style", subtitle: "Visual material for the preview panel background.") {
                MAYNDropdown(selection: settings.value(\.appearance.backgroundStyle), options: DockBackgroundStyleFull.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Use opaque background", subtitle: "Show an opaque background instead of translucent.") {
                Toggle("", isOn: settings.bool(\.appearance.useOpaqueBackground)).labelsHidden()
            }
        }
    }

    private var appearanceAdvancedSection: some View {
        Group {
            backgroundMaterialTuningSection
            panelSpacingSection
            panelChromeSection
            cardSizingSection
        }
    }

    @ViewBuilder
    private var backgroundMaterialTuningSection: some View {
        if hub.appearance.backgroundStyle == .frostedMaterial {
            MAYNSection(title: "Frosted material", subtitle: "Material variant for the frosted glass background.") {
                MAYNSettingsRow(title: "Material thickness", subtitle: nil) {
                    MAYNDropdown(selection: settings.value(\.appearance.backgroundMaterial), options: DockBackgroundMaterialFull.allCases) { $0.displayName }
                }
            }
        }

        if hub.appearance.backgroundStyle == .liquidGlass {
            MAYNSection(title: "Liquid glass", subtitle: "Opacity, blur, tint, and border for the glass panel.") {
                DockSettingsCompactNumericRow(
                    title: "Opacity",
                    value: settings.percentInt(from:\.appearance.glassOpacity),
                    range: 0...100,
                    step: 5,
                    suffix: "%"
                )
                MAYNDivider()
                DockSettingsCompactNumericRow(
                    title: "Blur",
                    value: settings.roundedInt(from:\.appearance.glassBlurRadius),
                    range: 0...80,
                    step: 5,
                    suffix: "pt"
                )
                MAYNDivider()
                DockSettingsCompactNumericRow(
                    title: "Saturation",
                    value: settings.percentInt(from:\.appearance.glassSaturation),
                    range: 0...200,
                    step: 5,
                    suffix: "%"
                )
                MAYNDivider()
                DockSettingsCompactNumericRow(
                    title: "Tint",
                    value: settings.percentInt(from:\.appearance.backgroundTintOpacity),
                    range: 0...100,
                    step: 5,
                    suffix: "%"
                )
                MAYNDivider()
                DockSettingsCompactNumericRow(
                    title: "Border opacity",
                    value: settings.percentInt(from:\.appearance.backgroundBorderOpacity),
                    range: 0...100,
                    step: 5,
                    suffix: "%"
                )
                MAYNDivider()
                DockSettingsCompactNumericRow(
                    title: "Border width",
                    value: settings.roundedInt(from:\.appearance.backgroundBorderWidth),
                    range: 0...4,
                    step: 1,
                    suffix: "pt"
                )
            }
        }
    }

    private var panelSpacingSection: some View {
        MAYNSection(title: "Spacing & focus", subtitle: "Padding scale and dimming for non-selected cards.") {
            DockSettingsCompactNumericRow(
                title: "Spacing scale",
                value: settings.percentInt(from:\.appearance.globalPaddingMultiplier),
                range: 50...200,
                step: 10,
                suffix: "%"
            )
            MAYNDivider()
            DockSettingsCompactNumericRow(
                title: "Unselected opacity",
                value: settings.percentInt(from:\.appearance.unselectedContentOpacity),
                range: 0...100,
                step: 5,
                suffix: "%"
            )
            MAYNDivider()
            MAYNSettingsRow(title: "Rounded corners", subtitle: "Use rounded corners on preview cards.") {
                Toggle("", isOn: settings.bool(\.appearance.uniformCardRadius)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Long title overflow", subtitle: "How to handle window titles that don't fit.") {
                MAYNDropdown(selection: settings.value(\.appearance.titleOverflowStyle), options: DockTitleOverflowStyle.allCases) { $0.displayName }
            }
        }
    }

    private var panelChromeSection: some View {
        MAYNSection(title: "Panel chrome", subtitle: "Labels, backgrounds, and motion for the hover panel.") {
            MAYNSettingsRow(title: "Distinguish minimized/hidden", subtitle: "Badge overlays for minimized and hidden windows.") {
                Toggle("", isOn: settings.bool(\.appearance.showMinimizedHiddenLabels)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Quit button for windowless apps", subtitle: "Show quit when an app has no open windows.") {
                Toggle("", isOn: settings.bool(\.appearance.showWindowlessAppQuitButton)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide preview card background", subtitle: "Make preview card backgrounds transparent.") {
                Toggle("", isOn: settings.bool(\.appearance.hidePreviewCardBackground)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide container background", subtitle: "Make the hover container background transparent.") {
                Toggle("", isOn: settings.bool(\.appearance.hideHoverContainerBackground)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide widget container background", subtitle: "Make the widget container background transparent.") {
                Toggle("", isOn: settings.bool(\.appearance.hideWidgetContainerBackground)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Active window border", subtitle: "Highlight the focused window with a colored border.") {
                Toggle("", isOn: settings.bool(\.appearance.showActiveWindowBorder)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable animations", subtitle: "Animate panel open/close and selection changes.") {
                Toggle("", isOn: settings.bool(\.appearance.showAnimations)).labelsHidden()
            }
        }
    }

    private var cardSizingSection: some View {
        MAYNSection(title: "Card sizing", subtitle: "Default preview card dimensions and resize behavior.") {
            MAYNSettingsRow(title: "Lock aspect ratio (16:10)", subtitle: "Keep preview width-to-height ratio fixed.") {
                Toggle("", isOn: settings.bool(\.appearance.lockAspectRatio)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dynamic image sizing", subtitle: "Resize preview cards to fit available space.") {
                Toggle("", isOn: settings.bool(\.appearance.allowDynamicImageSizing)).labelsHidden()
            }
            MAYNDivider()
            DockSettingsCompactNumericRow(
                title: "Preview width",
                value: settings.int(\.appearance.previewWidth),
                range: 100...600,
                step: 10,
                suffix: "px"
            )
            MAYNDivider()
            DockSettingsCompactNumericRow(
                title: "Preview height",
                value: settings.int(\.appearance.previewHeight),
                range: 60...400,
                step: 10,
                suffix: "px"
            )
            .disabled(hub.appearance.lockAspectRatio)
        }
    }

    // MARK: Dock preview appearance

    private var dockPreviewAppearanceSection: some View {
        MAYNSection(title: "Dock preview appearance") {
            MAYNSettingsRow(title: "Show app header", subtitle: "Show the app name and icon above the window strip.") {
                Toggle("", isOn: settings.bool(\.appearance.showAppName)).labelsHidden()
            }
            if hub.appearance.showAppName {
                MAYNDivider()
                MAYNSettingsRow(title: "App header style", subtitle: "Visual style of the app header.") {
                    MAYNDropdown(selection: settings.value(\.appearance.appNameStyle), options: DockAppNameStyle.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Show app icon only", subtitle: "Show only the app icon in the header, without the name.") {
                    Toggle("", isOn: settings.bool(\.appearance.showAppIconOnly)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Control position", subtitle: "Position of title and traffic light buttons on cards.") {
                MAYNDropdown(selection: settings.value(\.appearance.controlPosition), options: DockPreviewControlPosition.allCases) { positionLabel($0) }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show window title", subtitle: "Display the window name on each card.") {
                Toggle("", isOn: settings.bool(\.appearance.showWindowTitle)).labelsHidden()
            }
            if hub.appearance.showWindowTitle {
                MAYNDivider()
                MAYNSettingsRow(title: "Title visibility", subtitle: "When to show the window title.") {
                    MAYNDropdown(selection: settings.value(\.appearance.windowTitleVisibility), options: DockWindowTitleVisibilityMode.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title display context", subtitle: "Which features show the window title.") {
                    MAYNDropdown(selection: settings.value(\.appearance.windowTitleDisplayCondition), options: DockWindowTitleDisplayCondition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title font size", subtitle: "Font size for window titles.") {
                    MAYNDropdown(selection: settings.value(\.appearance.windowTitleFontSize), options: DockWindowTitleFontSize.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Title position", subtitle: "Where to place the window title.") {
                    MAYNDropdown(selection: settings.value(\.appearance.windowTitlePosition), options: DockWindowTitlePosition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling on titles", subtitle: "Remove Dock-style glow from window titles.") {
                    Toggle("", isOn: settings.bool(\.appearance.disableDockStyleTitles)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Traffic light visibility", subtitle: "When close/minimize/fullscreen buttons appear.") {
                MAYNDropdown(selection: settings.value(\.appearance.trafficLightVisibility), options: DockTrafficLightVisibilityMode.allCases) { $0.displayName }
            }
            if hub.appearance.trafficLightVisibility != .never {
                MAYNDivider()
                MAYNSettingsRow(title: "Traffic light position", subtitle: "Where traffic light buttons appear on each card.") {
                    MAYNDropdown(selection: settings.value(\.appearance.trafficLightPosition), options: DockTrafficLightPosition.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Close", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.close)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Minimize", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.minimize)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Fullscreen", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.toggleFullScreen)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Bring to current space", subtitle: nil) {
                    Toggle("", isOn: appearanceTrafficLightToggle(.bringToCurrentSpace)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Quit", subtitle: nil) { Toggle("", isOn: appearanceTrafficLightToggle(.quit)).labelsHidden() }
                MAYNDivider()
                MAYNSettingsRow(title: "Monochrome style", subtitle: "Single-color traffic light buttons.") {
                    Toggle("", isOn: settings.bool(\.appearance.useMonochromeTrafficLights)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Button scale", subtitle: "Size multiplier for traffic light buttons.") {
                    MAYNNumericStepper(text: "Scale", value: settings.percentInt(from:\.appearance.trafficLightButtonScale), range: 50...200, step: 10, presets: [75, 100, 125, 150], suffix: "%")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Disable dock styling", subtitle: "Remove Dock-style glow from traffic light buttons.") {
                    Toggle("", isOn: settings.bool(\.appearance.disableDockStyleTrafficLights)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show mass action buttons", subtitle: "Show Close All and Minimize All buttons in the header.") {
                Toggle("", isOn: settings.bool(\.appearance.showMassActionButtons)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Embed controls in frames", subtitle: "Show controls inside preview frames instead of outside.") {
                Toggle("", isOn: settings.bool(\.appearance.useEmbeddedDockPreviewElements)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Max rows (bottom dock)", subtitle: "Maximum preview rows for bottom-positioned Dock.") {
                MAYNNumericStepper(text: "Rows", value: settings.int(\.appearance.previewMaxRows), range: 1...8, step: 1, presets: [1, 2, 3, 4, 6], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Max columns (side dock)", subtitle: "Maximum preview columns for side-positioned Dock.") {
                MAYNNumericStepper(text: "Cols", value: settings.int(\.appearance.previewMaxColumns), range: 1...8, step: 1, presets: [1, 2, 4, 6, 8], suffix: "")
            }
        }
    }

    // MARK: Compact mode

    private var compactModeSection: some View {
        MAYNSection(title: "Compact mode") {
            MAYNSettingsRow(title: "Always use compact mode", subtitle: "Show text list instead of thumbnails for all previews.") {
                Toggle("", isOn: settings.bool(\.appearance.disableImagePreview)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Dock preview threshold", subtitle: "Switch to compact list when window count reaches this (0 = off).") {
                MAYNNumericStepper(text: "Threshold", value: settings.int(\.appearance.dockPreviewCompactThreshold), range: 0...30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Window switcher threshold", subtitle: "Compact threshold for the window switcher.") {
                MAYNNumericStepper(text: "Threshold", value: settings.int(\.appearance.windowSwitcherCompactThreshold), range: 0...30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Cmd+Tab threshold", subtitle: "Compact threshold for Cmd+Tab enhancements.") {
                MAYNNumericStepper(text: "Threshold", value: settings.int(\.appearance.cmdTabCompactThreshold), range: 0...30, step: 1, presets: [0, 8, 12, 16], suffix: "")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Item size", subtitle: "Size of items in compact list mode.") {
                MAYNDropdown(selection: settings.value(\.appearance.compactModeItemSize), options: DockCompactModeItemSize.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Title format", subtitle: "What information to show in compact list rows.") {
                MAYNDropdown(selection: settings.value(\.appearance.compactModeTitleFormat), options: DockCompactModeTitleFormat.allCases) { $0.displayName }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Hide traffic lights in compact mode", subtitle: "Hide traffic light buttons when using the compact list.") {
                Toggle("", isOn: settings.bool(\.appearance.compactModeHideTrafficLights)).labelsHidden()
            }
        }
    }

    // MARK: Dock scroll gesture

    private var dockScrollGestureSection: some View {
        MAYNSection(title: "Dock scroll gesture") {
            MAYNSettingsRow(title: "Enable scroll gestures on dock icons", subtitle: "Scroll on a Dock icon to activate, hide, or control apps.") {
                Toggle("", isOn: settings.bool(\.gestures.enableDockScrollGesture)).labelsHidden()
            }
            if hub.gestures.enableDockScrollGesture {
                MAYNDivider()
                MAYNSettingsRow(title: "Scroll behavior", subtitle: "What scrolling on a Dock icon does.") {
                    MAYNDropdown(selection: settings.value(\.gestures.dockScrollBehavior), options: DockScrollGestureBehavior.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Media app scroll", subtitle: "Scrolling behavior for music / audio apps.") {
                    MAYNDropdown(selection: settings.value(\.gestures.dockScrollMediaBehavior), options: DockScrollGestureMediaBehavior.allCases) { $0.displayName }
                }
            }
        }
    }

    // MARK: Title bar scroll

    private var titleBarScrollSection: some View {
        MAYNSection(title: "Title bar scroll gesture") {
            MAYNSettingsRow(title: "Enable title bar scroll", subtitle: "Scroll over an active window's title bar to center and resize it.") {
                Toggle("", isOn: settings.bool(\.gestures.enableTitleBarScrollGesture)).labelsHidden()
            }
            if hub.gestures.enableTitleBarScrollGesture {
                MAYNDivider()
                MAYNSettingsRow(title: "Sizing mode", subtitle: "Whether to resize uniformly or width and height separately.") {
                    MAYNDropdown(selection: settings.value(\.gestures.titleBarSizingMode), options: DockTitleBarSizingMode.allCases) { $0.displayName }
                }
                if hub.gestures.titleBarSizingMode == .uniform {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Centered window size", subtitle: "Scale of the window when centered (0.5–1.0).") {
                        MAYNNumericStepper(text: "Scale", value: settings.percentInt(from:\.gestures.titleBarCenteredScale), range: 50...100, step: 5, presets: [60, 70, 80, 100], suffix: "%")
                    }
                } else {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Lock aspect ratio", subtitle: "Keep width and height proportional.") {
                        Toggle("", isOn: settings.bool(\.gestures.titleBarLockAspectRatio)).labelsHidden()
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Centered width scale", subtitle: "Width as fraction of screen width.") {
                        MAYNNumericStepper(text: "Width", value: settings.percentInt(from:\.gestures.titleBarCenteredWidthScale), range: 50...100, step: 5, presets: [60, 70, 80], suffix: "%")
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Centered height scale", subtitle: "Height as fraction of screen height.") {
                        MAYNNumericStepper(text: "Height", value: settings.percentInt(from:\.gestures.titleBarCenteredHeightScale), range: 50...100, step: 5, presets: [60, 70, 80], suffix: "%")
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Restore window interval", subtitle: "Seconds before the window snaps back to its original size.") {
                    MAYNNumericStepper(text: "Interval", value: settings.roundedInt(from:\.gestures.titleBarRestoreInterval), range: 0...5, step: 1, presets: [1, 2, 3], suffix: "s")
                }
            }
        }
    }

    // MARK: Dock preview gestures

    private var dockPreviewGesturesSection: some View {
        MAYNSection(title: "Dock preview gestures") {
            MAYNSettingsRow(title: "Enable gestures on dock window previews", subtitle: "Swipe on preview cards to perform window actions.") {
                Toggle("", isOn: settings.bool(\.gestures.enableDockPreviewGestures)).labelsHidden()
            }
            if hub.gestures.enableDockPreviewGestures {
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe towards Dock action", subtitle: "Action when swiping a card toward the Dock.") {
                    MAYNDropdown(selection: settings.value(\.gestures.swipeTowardsDockAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe away from Dock action", subtitle: "Action when swiping a card away from the Dock.") {
                    MAYNDropdown(selection: settings.value(\.gestures.swipeAwayFromDockAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Aero shake action", subtitle: "Action when shaking a window with the mouse.") {
                    MAYNDropdown(selection: settings.value(\.gestures.aeroShakeAction), options: DockAeroShakeAction.allCases) { $0.displayName }
                }
            }
        }
    }

    // MARK: Window switcher gestures

    private var switcherGesturesSection: some View {
        MAYNSection(title: "Window switcher gestures") {
            MAYNSettingsRow(title: "Enable gestures in window switcher", subtitle: "Swipe on preview cards in the switcher to perform actions.") {
                Toggle("", isOn: settings.bool(\.gestures.enableSwitcherGestures)).labelsHidden()
            }
            if hub.gestures.enableSwitcherGestures {
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe up action", subtitle: "Action when swiping a card upward.") {
                    MAYNDropdown(selection: settings.value(\.gestures.switcherSwipeUpAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Swipe down action", subtitle: "Action when swiping a card downward.") {
                    MAYNDropdown(selection: settings.value(\.gestures.switcherSwipeDownAction), options: DockWindowSwipeAction.allCases) { $0.displayName }
                }
            }
        }
    }

    // MARK: Gesture sensitivity

    private var gestureSensitivitySection: some View {
        MAYNSection(title: "Gesture sensitivity") {
            MAYNSettingsRow(title: "Swipe threshold", subtitle: "Minimum swipe distance in pixels to trigger a gesture.") {
                MAYNNumericStepper(text: "Threshold", value: settings.roundedInt(from:\.gestures.gestureSwipeThreshold), range: 20...100, step: 10, presets: [20, 50, 80, 100], suffix: "px")
            }
        }
    }

    // MARK: Mouse actions

    private var mouseActionsSection: some View {
        MAYNSection(title: "Mouse actions") {
            MAYNSettingsRow(title: "Middle click action", subtitle: "Action performed when middle-clicking a window preview.") {
                MAYNDropdown(selection: settings.value(\.gestures.middleClickAction), options: DockMiddleClickAction.allCases) { $0.displayName }
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
            MAYNDropdown(selection: settings.value(actionKeyPath), options: DockWindowSwipeAction.allCases) { $0.displayName }
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
                Toggle("", isOn: settings.bool(\.widgets.showSpecialAppControls)).labelsHidden()
            }
            if hub.widgets.showSpecialAppControls {
                MAYNDivider()
                MAYNSettingsRow(title: "Media controls", subtitle: "Show playback controls for the active music app.") {
                    Toggle("", isOn: settings.bool(\.widgets.enableMediaWidget)).labelsHidden()
                }
                if hub.widgets.enableMediaWidget {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Media detection mode", subtitle: "Which apps show the media widget.") {
                        MAYNDropdown(selection: settings.value(\.widgets.mediaDetectionMode), options: DockMediaDetectionMode.allCases) { $0.displayName }
                    }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Calendar widget", subtitle: "Show today's calendar events when hovering Calendar.") {
                    Toggle("", isOn: settings.bool(\.widgets.enableCalendarWidget)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Embedded controls alongside previews", subtitle: "Show widget controls within the preview panel instead of full-size.") {
                    Toggle("", isOn: settings.bool(\.widgets.useEmbeddedMediaControls)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Full controls when all windows minimized", subtitle: "Show full-size controls when an app has no visible windows.") {
                    Toggle("", isOn: settings.bool(\.widgets.showBigControlsWhenNoValidWindows))
                        .labelsHidden()
                        .disabled(!hub.widgets.useEmbeddedMediaControls)
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Allow pinning controls to screen", subtitle: "Pin widget controls to the screen so they stay visible.") {
                    Toggle("", isOn: settings.bool(\.widgets.enablePinning)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Media widget scroll behavior", subtitle: "What scrolling over the media widget does.") {
                    MAYNDropdown(selection: settings.value(\.gestures.mediaScrollBehavior), options: DockMediaScrollBehavior.allCases) { $0.displayName }
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Media widget scroll direction", subtitle: "Scroll direction for the media widget.") {
                    MAYNDropdown(selection: settings.value(\.gestures.mediaScrollDirection), options: DockMediaScrollDirection.allCases) { $0.displayName }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Enable Dock item widgets", subtitle: "Enable special handling for folder, stack, and archive items in the Dock.") {
                Toggle("", isOn: settings.bool(\.widgets.enableDockItemWidgets)).labelsHidden()
            }
            if hub.widgets.enableDockItemWidgets {
                MAYNDivider()
                MAYNSettingsRow(title: "Folder widget", subtitle: "Show folder contents when hovering a folder or stack in the Dock.") {
                    Toggle("", isOn: settings.bool(\.widgets.enableFolderWidget)).labelsHidden()
                }
                if hub.widgets.enableFolderWidget {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Default sort order", subtitle: "How to sort files in folder widgets.") {
                        MAYNDropdown(selection: settings.value(\.widgets.folderSortOrder), options: DockFolderSortOrder.allCases) { $0.displayName }
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Sort descending by default", subtitle: "Reverse the sort order so newest/largest items appear first.") {
                        Toggle("", isOn: settings.bool(\.widgets.folderSortReversed)).labelsHidden()
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Remember sort per folder", subtitle: "Save the sort order independently for each folder.") {
                        Toggle("", isOn: settings.bool(\.widgets.folderRememberSortPerFolder)).labelsHidden()
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Show hidden files", subtitle: "Include files whose names start with a period.") {
                        Toggle("", isOn: settings.bool(\.widgets.folderShowHiddenFiles)).labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: Active app indicator

    private var activeIndicatorSection: some View {
        MAYNSection(title: "Active app indicator") {
            MAYNSettingsRow(title: "Enable", subtitle: "Show a colored line below the active application's Dock icon.") {
                Toggle("", isOn: settings.bool(\.master.enableActiveAppIndicator)).labelsHidden()
            }
            if hub.master.enableActiveAppIndicator {
                MAYNDivider()
                MAYNSettingsRow(title: "Auto size", subtitle: "Automatically size the indicator to match the Dock icon.") {
                    Toggle("", isOn: settings.bool(\.indicator.autoSize)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Auto length", subtitle: "Automatically set the length of the indicator.") {
                    Toggle("", isOn: settings.bool(\.indicator.autoLength)).labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Line height", subtitle: "Thickness of the indicator bar.") {
                    MAYNNumericStepper(text: "Height", value: settings.roundedInt(from:\.indicator.height), range: 1...12, step: 1, presets: [2, 3, 4, 6], suffix: "pt")
                }
                MAYNDivider()
                MAYNSettingsRow(title: "Offset from Dock", subtitle: "Distance from the Dock edge to the indicator.") {
                    MAYNNumericStepper(text: "Offset", value: settings.roundedInt(from:\.indicator.offset), range: 0...20, step: 1, presets: [0, 2, 5, 8], suffix: "pt")
                }
                if !hub.indicator.autoLength {
                    MAYNDivider()
                    MAYNSettingsRow(title: "Length", subtitle: "Width of the indicator bar.") {
                        MAYNNumericStepper(text: "Length", value: settings.roundedInt(from:\.indicator.length), range: 10...100, step: 5, presets: [20, 40, 60], suffix: "pt")
                    }
                    MAYNDivider()
                    MAYNSettingsRow(title: "Horizontal shift", subtitle: "Shift the indicator left or right.") {
                        MAYNNumericStepper(text: "Shift", value: settings.roundedInt(from:\.indicator.shift), range: -30...30, step: 2, presets: [-10, 0, 10], suffix: "pt")
                    }
                }
            }
        }
    }

    // MARK: Filters

    private var filtersSection: some View {
        MAYNSection(title: "Filters") {
            MAYNSettingsRow(title: "Sort minimized windows to end", subtitle: "Move minimized and hidden windows to the end of the list.") {
                Toggle("", isOn: settings.bool(\.filters.sortMinimizedToEnd)).labelsHidden()
            }
            if !hub.filters.appNameFilters.isEmpty {
                MAYNDivider()
                MAYNSettingsRow(title: "Excluded apps", subtitle: nil) { EmptyView() }
                ForEach(Array(hub.filters.appNameFilters.enumerated()), id: \.offset) { idx, name in
                    MAYNDivider()
                    MAYNSettingsRow(title: name, subtitle: nil) {
                        MAYNButton("Remove", role: .destructive) {
                            hub.filters.appNameFilters.remove(at: idx)
                            settings.persist()
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
                            settings.persist()
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
                        settings.persist()
                    }
                    .disabled(newWindowFilter.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Widget app filters", subtitle: "Hide media/calendar widgets for apps whose name or bundle ID contains these strings.") {
                EmptyView()
            }
            ForEach(Array(hub.filters.widgetAppFilters.enumerated()), id: \.offset) { idx, filter in
                MAYNDivider()
                MAYNSettingsRow(title: filter, subtitle: nil) {
                    MAYNButton("Remove", role: .destructive) {
                        hub.filters.widgetAppFilters.remove(at: idx)
                        settings.persist()
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Add widget filter", subtitle: nil) {
                HStack(spacing: 8) {
                    MAYNTextField(placeholder: "App name", text: $newWidgetFilter)
                        .frame(width: 160)
                    MAYNButton("Add") {
                        let trimmed = newWidgetFilter.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        hub.filters.widgetAppFilters.append(trimmed)
                        newWidgetFilter = ""
                        settings.persist()
                    }
                    .disabled(newWidgetFilter.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Custom application directories", subtitle: "Scan extra folders for applications (e.g. ~/Applications).") {
                EmptyView()
            }
            ForEach(Array(hub.filters.customAppDirectories.enumerated()), id: \.offset) { idx, path in
                MAYNDivider()
                MAYNSettingsRow(title: path, subtitle: nil) {
                    MAYNButton("Remove", role: .destructive) {
                        hub.filters.customAppDirectories.remove(at: idx)
                        settings.persist()
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Add application directory", subtitle: nil) {
                MAYNButton("Choose folder…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    let path = url.path
                    guard !hub.filters.customAppDirectories.contains(path) else { return }
                    hub.filters.customAppDirectories.append(path)
                    settings.persist()
                }
            }
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        MAYNSection(title: "Advanced") {
            MAYNSettingsRow(title: "Window processing debounce", subtitle: "Minimum interval between window list updates.") {
                MAYNNumericStepper(text: "Debounce", value: settings.int(\.advanced.windowProcessingDebounceMS), range: 0...2000, step: 50, presets: [100, 200, 300, 500], suffix: "ms")
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Show preview above app labels", subtitle: "Raise the preview panel above Dock app labels (restarts app).") {
                Toggle("", isOn: settings.bool(\.advanced.raisedWindowLevel)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Prevent dock from hiding during previews", subtitle: "Keep the Dock visible while any preview is open.") {
                Toggle("", isOn: settings.bool(\.previews.preventDockAutoHideWhileOpen)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Debug mode", subtitle: "Enable verbose logging for bug reporting.") {
                Toggle("", isOn: settings.bool(\.advanced.debugMode)).labelsHidden()
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
                settings.persist()
            }
        )
    }
}
