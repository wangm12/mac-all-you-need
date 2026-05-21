import Core
import Platform
import SwiftUI

enum WindowControlSettingsScope {
    case layoutsShortcuts
    case layoutsSnap
    case layoutsApps
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

    var body: some View {
        Group {
            switch scope {
            case .layoutsShortcuts:
                shortcutsSection
            case .layoutsSnap:
                edgeSnapSection
            case .layoutsApps:
                ignoredAppsSection
            case .grabGesture:
                grabAnywhereSection
                doubleClickSection
            case .grabApps:
                ignoredAppsSection
            case .advanced:
                ignoredAppsSection
                diagnosticsSection
            }
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
        }
    }

    private var grabAnywhereSection: some View {
        MAYNSection(
            title: "Window Grab",
            subtitle: "Hold a modifier and drag a window from any visible area."
        ) {
            MAYNSettingsRow(
                title: "Window Grab modifier",
                subtitle: "Modifier combo required to drag from anywhere."
            ) {
                WindowGestureModifierPicker(selection: modifierBinding(\.dragModifier), defaultModifier: WindowControlSettings.default.dragModifier)
            }
        }
    }

    private var doubleClickSection: some View {
        MAYNSection(title: "Double-Click Layout") {
            MAYNSettingsRow(
                title: "Modifier double-click",
                subtitle: "Double-click a window with the configured modifier to maximize it."
            ) {
                Toggle("", isOn: boolBinding(\.doubleClickEnabled))
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Double-click modifier",
                subtitle: "Modifier combo required for double-click maximize."
            ) {
                WindowGestureModifierPicker(selection: modifierBinding(\.doubleClickModifier), defaultModifier: WindowControlSettings.default.doubleClickModifier)
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
                        HStack(alignment: .top, spacing: 8) {
                            HotkeyRecorderControl(
                                descriptor: hotkeyBinding(for: action, fallback: descriptor),
                                issueMessage: hotkeyIssueMessage(for: action),
                                candidateIssueMessage: { hotkeyCandidateIssueMessage($0, for: action) },
                                defaultDescriptor: action.primaryDefaultDescriptor ?? descriptor,
                                recorderWidth: 112,
                                errorWidth: 260,
                                reset: {
                                    if let defaultDescriptor = action.primaryDefaultDescriptor {
                                        setHotkey(defaultDescriptor, for: action)
                                    }
                                }
                            )
                            Button {
                                removeHotkey(for: action)
                            } label: {
                                Image(systemName: "delete.left")
                            }
                            .buttonStyle(.plain)
                            .help("Turn off shortcut")
                        }
                    } else {
                        HStack(spacing: 8) {
                            StatusPill(text: "Off", kind: .neutral)
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

    private func displayedShortcutDescriptor(for action: HotkeyAction) -> HotkeyDescriptor? {
        let descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        return descriptors.first ?? pendingShortcutDescriptors[action]
    }

    private func hotkeyBinding(for action: HotkeyAction, fallback: HotkeyDescriptor) -> Binding<HotkeyDescriptor> {
        Binding {
            displayedShortcutDescriptor(for: action) ?? fallback
        } set: { descriptor in
            setHotkey(descriptor, for: action)
        }
    }

    private func setHotkey(_ descriptor: HotkeyDescriptor, for action: HotkeyAction) {
        var descriptors = hotkeyMap[action] ?? action.defaultDescriptors
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
        if pendingShortcutDescriptors[action] != nil,
           (hotkeyMap[action] ?? action.defaultDescriptors).isEmpty
        {
            pendingShortcutDescriptors[action] = nil
            return
        }

        pendingShortcutDescriptors[action] = nil
        var next = hotkeyMap
        next[action] = []
        autoApplyHotkeys(next, changedAction: action)
    }

    private func hotkeyIssueMessage(for action: HotkeyAction) -> String? {
        let descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        guard let descriptor = descriptors.first ?? action.primaryDefaultDescriptor else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
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
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [HotkeyDescriptor]], changedAction: HotkeyAction) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
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
        .windowPreviousDisplay
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
