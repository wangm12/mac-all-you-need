import ApplicationServices
import Core
import Platform
import SwiftUI

enum WindowControlSettingsScope {
    case layoutsShortcuts
    case layoutsRadial
    case layoutsSnap
    case layoutsApps
    case layoutsRules
    case grabGesture
    case grabApps
    case advanced
}

struct WindowControlSettingsView: View {
    let controller: AppController
    let scope: WindowControlSettingsScope
    @Binding private var settings: WindowControlSettings
    @Binding private var hotkeyMap: [HotkeyAction: [HotkeyDescriptor]]
    @State private var pendingShortcutDescriptors: [HotkeyAction: HotkeyDescriptor] = [:]
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]

    init(
        controller: AppController,
        settings: Binding<WindowControlSettings>,
        hotkeyMap: Binding<[HotkeyAction: [HotkeyDescriptor]]>,
        scope: WindowControlSettingsScope = .layoutsShortcuts
    ) {
        self.controller = controller
        self.scope = scope
        _settings = settings
        _hotkeyMap = hotkeyMap
    }

    @ViewBuilder
    var body: some View {
        switch scope {
            case .layoutsShortcuts:
                shortcutsSection
            case .layoutsRadial:
                RadialMenuSettingsTabView(
                    settings: $settings,
                    onSettingsChange: { next in
                        WindowControlSettingsStore.save(next)
                        controller.applyWindowControlSettings(next)
                    },
                    axTrusted: AXIsProcessTrusted(),
                    layoutsEnabled: settings.enabled && controller.windowControl.windowLayoutsEnabled
                )
            case .layoutsSnap:
                edgeSnapSection
            case .layoutsApps:
                ignoredAppsSection
            case .layoutsRules:
                windowRulesSection
            case .grabGesture:
                grabAnywhereSection
            case .grabApps:
                ignoredAppsSection
            case .advanced:
                ignoredAppsSection
                diagnosticsSection
        }
    }

    private var edgeSnapSection: some View {
        MAYNSection(
            title: "Edge Snap",
            subtitle: "Show the snap overlay while dragging a window near screen edges."
        ) {
            MAYNSettingsRow(
                title: "Snap while dragging",
                subtitle: "Tile a dragged window when it reaches a screen edge or corner."
            ) {
                Toggle("", isOn: boolBinding(\.edgeSnapEnabled))
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Require snap modifier",
                subtitle: "Only show edge snap when the configured modifier is held."
            ) {
                Toggle("", isOn: boolBinding(\.edgeSnapRequiresModifier))
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Snap modifier",
                subtitle: "Modifier combo used when snap requires a key."
            ) {
                WindowGestureModifierPicker(selection: modifierBinding(\.edgeSnapModifier), defaultModifier: WindowControlSettings.default.edgeSnapModifier)
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Snap Assist zones",
                subtitle: "Show center and half-zone hints while dragging with a modifier."
            ) {
                Toggle("", isOn: boolBinding(\.snapAssistShowZones)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Active window border",
                subtitle: "Highlight the frontmost window with an accent border."
            ) {
                Toggle("", isOn: boolBinding(\.activeWindowBorderEnabled)).labelsHidden()
            }
            if settings.activeWindowBorderEnabled {
                MAYNDivider()
                MAYNSettingsRow(title: "Inner border", subtitle: "Use an inset border instead of an outer stroke.") {
                    Toggle("", isOn: boolBinding(\.activeWindowBorderInner)).labelsHidden()
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Disable Sequoia tiling hotkeys",
                subtitle: "Avoid conflicts with macOS built-in window tiling shortcuts."
            ) {
                Toggle("", isOn: boolBinding(\.disableSequoiaTilingHotkeys)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Animate window moves",
                subtitle: "Use smoother AX moves for keyboard shortcuts (slightly slower)."
            ) {
                Toggle("", isOn: boolBinding(\.animateWindowMoves)).labelsHidden()
            }
        }
    }

    private var grabAnywhereSection: some View {
        MAYNSection(
            title: "Window Grab",
            subtitle: "Hold a modifier and drag a window from any visible area."
        ) {
            MAYNSettingsRow(
                title: "Enable Window Grab",
                subtitle: "Allow dragging windows from visible content areas."
            ) {
                Toggle("", isOn: boolBinding(\.dragAnywhereEnabled)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Window Grab modifier",
                subtitle: "Modifier combo required to drag from anywhere."
            ) {
                WindowGestureModifierPicker(selection: modifierBinding(\.dragModifier), defaultModifier: WindowControlSettings.default.dragModifier)
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Double-click title bar",
                subtitle: "Toggle maximize/restore when double-clicking the title bar area."
            ) {
                Toggle("", isOn: boolBinding(\.doubleClickEnabled)).labelsHidden()
            }
            if settings.doubleClickEnabled {
                MAYNDivider()
                MAYNSettingsRow(title: "Double-click modifier", subtitle: "Require this modifier while double-clicking.") {
                    WindowGestureModifierPicker(
                        selection: modifierBinding(\.doubleClickModifier),
                        defaultModifier: WindowControlSettings.default.doubleClickModifier
                    )
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Modifier + scroll resize",
                subtitle: "Resize the frontmost window with scroll wheel while holding the grab modifier."
            ) {
                Toggle("", isOn: boolBinding(\.scrollResizeEnabled)).labelsHidden()
            }
        }
    }

    private var windowRulesSection: some View {
        MAYNSection(
            title: "Window Rules",
            subtitle: "Match apps or window titles to ignore snapping or force floating behavior."
        ) {
            ForEach($settings.windowRules) { $rule in
                MAYNSettingsRow(
                    title: rule.bundleID ?? rule.titlePattern ?? "Rule",
                    subtitle: rule.action.title
                ) {
                    Button(role: .destructive) {
                        settings.windowRules.removeAll { $0.id == rule.id }
                        WindowControlSettingsStore.save(settings)
                        controller.applyWindowControlSettings(settings)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                MAYNDivider()
            }
            MAYNButton("Add ignore rule for frontmost app") {
                guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
                var next = settings
                next.windowRules.append(WindowRule(bundleID: bundle, action: .ignore))
                settings = next
                WindowControlSettingsStore.save(next)
                controller.applyWindowControlSettings(next)
            }
        }
    }

    private var shortcutsSection: some View {
        MAYNSection(
            title: "Layout Shortcuts",
            subtitle: "Edit the shortcut for each supported window layout action."
        ) {
            ForEach(Array(Self.windowActions.enumerated()), id: \.element.rawValue) { index, action in
                if index > 0 { MAYNDivider() }
                MAYNSettingsRow(
                    title: action.windowControlTitle,
                    subtitle: action.windowControlSubtitle
                ) {
                    if let descriptor = displayedShortcutDescriptor(for: action) {
                        let pendingOnly = isPendingShortcutOnly(for: action)
                        HStack(alignment: shortcutRowControlAlignment(for: action), spacing: 8) {
                            HotkeyRecorderControl(
                                descriptor: hotkeyBinding(for: action, fallback: descriptor),
                                issueMessage: hotkeyIssueMessage(for: action),
                                candidateIssueMessage: { hotkeyCandidateIssueMessage($0, for: action) },
                                defaultDescriptor: WindowControlSettingsPresentation.resetBaselineDescriptor(
                                    for: action,
                                    current: descriptor,
                                    isPendingOnly: pendingOnly
                                ),
                                recorderWidth: 112,
                                errorWidth: 260,
                                reset: { performShortcutReset(for: action, pendingOnly: pendingOnly) }
                            )
                            Button {
                                removeHotkey(for: action)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .frame(
                                width: HotkeyRecorderControlPresentation.defaultRecorderHeight,
                                height: HotkeyRecorderControlPresentation.defaultRecorderHeight
                            )
                            .contentShape(Rectangle())
                            .help(WindowControlSettingsPresentation.closeHelp(isPendingOnly: pendingOnly))
                        }
                    } else {
                        Button {
                            pendingShortcutDescriptors[action] = WindowControlSettingsPresentation.seedDescriptor(for: action)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Add shortcut")
                    }
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Repeat half across displays",
                subtitle: "Press the same half shortcut again to move the window to the next display."
            ) {
                Toggle("", isOn: boolBinding(\.repeatHalfAcrossDisplays)).labelsHidden()
            }
        }
    }

    private var ignoredAppsSection: some View {
        MAYNSection(
            title: "Ignored Apps",
            subtitle: "Window Layouts and Window Grab stay inactive while these apps are frontmost."
        ) {
            BundleIDExclusionEditor(
                bundleIDs: ignoredBundleIDsBinding,
                save: { bundleIDs in
                    saveIgnoredBundleIDs(bundleIDs)
                },
                addSubtitle: "Choose apps where layout shortcuts and grab gestures should pass through.",
                panelTitle: "Choose Apps to Ignore",
                panelMessage: "Select apps where window features should not move or snap windows."
            )
        }
    }

    private var diagnosticsSection: some View {
        MAYNSection(title: "Diagnostics") {
            MAYNSettingsRow(
                title: "Event tap",
                subtitle: WindowControlDiagnosticsPresentation.eventTapDetail(for: controller.windowControl.state)
            ) {
                StatusPill(
                    text: WindowControlDiagnosticsPresentation.eventTapText(for: controller.windowControl.state),
                    kind: WindowControlDiagnosticsPresentation.eventTapKind(for: controller.windowControl.state)
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Last action",
                subtitle: WindowControlDiagnosticsPresentation.lastResultText(controller.windowControl.lastMovementResult)
            ) {
                StatusPill(
                    text: WindowControlDiagnosticsPresentation.lastActionText(controller.windowControl.lastAction),
                    kind: .neutral
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Title bar Y offset",
                subtitle: "Fine-tune title-bar hit testing for double-click maximize."
            ) {
                MAYNNumericStepper(
                    text: "YOffset",
                    value: Binding(
                        get: { Int(settings.titleBarYOffset.rounded()) },
                        set: { value in updateSettings { $0.titleBarYOffset = Double(value) } }
                    ),
                    range: -20...20,
                    step: 1,
                    presets: [-8, 0, 8],
                    suffix: "px"
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Debug logging", subtitle: "Log window-control events to the console.") {
                Toggle("", isOn: boolBinding(\.debugLoggingEnabled)).labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Export",
                subtitle: "Copy a text snapshot for support or debugging."
            ) {
                MAYNButton("Copy diagnostics") {
                    copyDiagnosticsReport()
                }
            }
        }
    }

    private func copyDiagnosticsReport() {
        let wc = controller.windowControl
        let snapshot = WindowControlDiagnosticsSnapshot(
            eventTapDetail: WindowControlDiagnosticsPresentation.eventTapDetail(for: wc.state),
            eventTapStatus: WindowControlDiagnosticsPresentation.eventTapText(for: wc.state),
            lastAction: WindowControlDiagnosticsPresentation.lastActionText(wc.lastAction),
            lastResultDetail: WindowControlDiagnosticsPresentation.lastResultText(wc.lastMovementResult),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            accessibilityTrusted: AXIsProcessTrusted()
        )
        Task {
            let report = await controller.featureWorkerHost.windowControl.formatDiagnosticsReport(snapshot)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    private var ignoredBundleIDsBinding: Binding<[String]> {
        Binding {
            settings.ignoredBundleIDs
        } set: { bundleIDs in
            var next = settings
            next.ignoredBundleIDs = SettingsExclusionList.normalizedBundleIDs(bundleIDs)
            settings = next
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<WindowControlSettings, Bool>) -> Binding<Bool> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            updateSettings { $0[keyPath: keyPath] = value }
        }
    }

    private func modifierBinding(_ keyPath: WritableKeyPath<WindowControlSettings, WindowGestureModifier>) -> Binding<WindowGestureModifier> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            updateSettings { $0[keyPath: keyPath] = value }
        }
    }

    private func updateSettings(_ mutate: (inout WindowControlSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        WindowControlSettingsStore.save(next)
        controller.applyWindowControlSettings(next)
    }

    private func saveIgnoredBundleIDs(_ bundleIDs: [String]) {
        updateSettings {
            $0.ignoredBundleIDs = SettingsExclusionList.normalizedBundleIDs(bundleIDs)
        }
    }

    private func shortcutRowControlAlignment(for action: HotkeyAction) -> VerticalAlignment {
        hotkeyIssueMessage(for: action) == nil ? .center : .top
    }

    private func storedDescriptors(for action: HotkeyAction) -> [HotkeyDescriptor] {
        hotkeyMap[action] ?? []
    }

    private func isPendingShortcutOnly(for action: HotkeyAction) -> Bool {
        WindowControlSettingsPresentation.isPendingShortcutOnly(
            storedDescriptors: storedDescriptors(for: action),
            pendingDescriptor: pendingShortcutDescriptors[action]
        )
    }

    private func displayedShortcutDescriptor(for action: HotkeyAction) -> HotkeyDescriptor? {
        storedDescriptors(for: action).first ?? pendingShortcutDescriptors[action]
    }

    private func performShortcutReset(for action: HotkeyAction, pendingOnly: Bool) {
        if let defaultDescriptor = action.primaryDefaultDescriptor {
            setHotkey(defaultDescriptor, for: action)
            return
        }
        if pendingOnly {
            pendingShortcutDescriptors[action] = WindowControlSettingsPresentation.seedDescriptor(for: action)
            return
        }
        removeHotkey(for: action)
    }

    private func hotkeyBinding(for action: HotkeyAction, fallback: HotkeyDescriptor) -> Binding<HotkeyDescriptor> {
        Binding {
            displayedShortcutDescriptor(for: action) ?? fallback
        } set: { descriptor in
            setHotkey(descriptor, for: action)
        }
    }

    private func setHotkey(_ descriptor: HotkeyDescriptor, for action: HotkeyAction) {
        var descriptors = storedDescriptors(for: action)
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        pendingShortcutDescriptors[action] = nil
        var next = hotkeyMap
        next[action] = descriptors
        autoApplyHotkeys(next, changedAction: action)
    }

    private func removeHotkey(for action: HotkeyAction) {
        if isPendingShortcutOnly(for: action) {
            pendingShortcutDescriptors[action] = nil
            return
        }

        pendingShortcutDescriptors[action] = nil
        var next = hotkeyMap
        next[action] = []
        autoApplyHotkeys(next, changedAction: action)
    }

    private func hotkeyIssueMessage(for action: HotkeyAction) -> String? {
        guard let descriptor = displayedShortcutDescriptor(for: action) else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: action
        )
    }

    private func hotkeyCandidateIssueMessage(_ descriptor: HotkeyDescriptor, for action: HotkeyAction) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        )?.message
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [HotkeyDescriptor]], changedAction: HotkeyAction) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut,
            dockShortcuts: HotkeyValidation.liveDockShortcuts()
        ) != nil {
            hotkeyRegistrationErrors = [:]
            return
        }

        do {
            try controller.applyHotkeyMap(next)
            HotkeyMapStore.save(next)
            hotkeyRegistrationErrors = [:]
        } catch {
            hotkeyRegistrationErrors = HotkeyRecorderControlPresentation.registrationErrors(
                from: error,
                changedAction: changedAction
            )
        }
    }

    static let windowActions: [HotkeyAction] = [
        .windowLeftHalf,
        .windowRightHalf,
        .windowTopHalf,
        .windowBottomHalf,
        .windowTopLeft,
        .windowTopRight,
        .windowBottomLeft,
        .windowBottomRight,
        .windowMaximize,
        .windowAlmostMaximize,
        .windowCenter,
        .windowRestore,
        .windowNextDisplay,
        .windowPreviousDisplay,
        .windowNextSpace,
        .windowPreviousSpace
    ]
}

extension HotkeyAction {
    var windowControlTitle: String {
        label
            .replacingOccurrences(of: "Window Control: ", with: "")
            .replacingOccurrences(of: "Window Layouts: ", with: "")
            .replacingOccurrences(of: "Windows: ", with: "")
    }

    var windowControlSubtitle: String {
        primaryDefaultDescriptor == nil
            ? "Add a custom shortcut for this window action."
            : "Primary shortcut for this window action."
    }
}
