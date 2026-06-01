import AppKit
import Carbon.HIToolbox
import Core
import CoreGraphics
import Platform
import SwiftUI
import UI

extension Notification.Name {
    static let hotkeyRecorderDidStartRecording = Notification.Name("MAYNHotkeyRecorderDidStartRecording")
    static let hotkeyRecorderDidStopRecording = Notification.Name("MAYNHotkeyRecorderDidStopRecording")
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var descriptor: HotkeyDescriptor
    @Binding private var visualizerState: KeyboardShortcutVisualizerState
    var isInvalid = false
    var candidateIssueMessage: (HotkeyDescriptor) -> String? = { _ in nil }
    /// Optional callback to override the chip's text. The floating keyboard
    /// popup still uses `descriptor.display` so the verbose form is preserved
    /// in the registration summary. Only the in-row chip changes.
    var chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil

    init(
        descriptor: Binding<HotkeyDescriptor>,
        isInvalid: Bool = false,
        visualizerState: Binding<KeyboardShortcutVisualizerState> = .constant(.inactive),
        candidateIssueMessage: @escaping (HotkeyDescriptor) -> String? = { _ in nil },
        chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil
    ) {
        _descriptor = descriptor
        _visualizerState = visualizerState
        self.isInvalid = isInvalid
        self.candidateIssueMessage = candidateIssueMessage
        self.chipDisplayOverride = chipDisplayOverride
    }

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(
            descriptor: $descriptor,
            visualizerState: $visualizerState,
            isInvalid: isInvalid,
            candidateIssueMessage: candidateIssueMessage,
            chipDisplayOverride: chipDisplayOverride
        )
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.updateDescriptorBinding($descriptor)
        nsView.updateVisualizerStateBinding($visualizerState)
        nsView.updateValidationState(isInvalid: isInvalid)
        nsView.updateCandidateIssueMessage(candidateIssueMessage)
        nsView.updateChipDisplayOverride(chipDisplayOverride)
    }

    final class RecorderView: NSView {
        @Binding var descriptor: HotkeyDescriptor
        @Binding var visualizerState: KeyboardShortcutVisualizerState
        private let label = NSTextField(labelWithString: "")
        private let floatingKeyboard = KeyboardShortcutFloatingOverlayController()
        private var isInvalid: Bool
        private var isRecording = false
        private var activeModifierFlags: NSEvent.ModifierFlags = []
        private var ignoreKeyEventsUntil: TimeInterval = 0
        private(set) var keyMonitor: NSEventMonitorHandle?
        private var globalKeyMonitor: NSEventMonitorHandle?
        private var tapController: CGEventTapController?
        private var candidateIssueMessage: (HotkeyDescriptor) -> String?
        private var chipDisplayOverride: ((HotkeyDescriptor) -> String)?
        private(set) var pendingDescriptor: HotkeyDescriptor?
        private(set) var pendingIssueMessage: String?

        // Modifier-tap detection state
        private var tapPressTime: TimeInterval?
        private var tapPressCGFlags: CGEventFlags = []
        private var tapNonModifierPressed = false
        private var tapLastRelease: (key: ModifierTapShortcut.Key, time: TimeInterval, count: Int)?
        private static let multiTapWindow: TimeInterval = 0.28

        init(
            descriptor: Binding<HotkeyDescriptor>,
            visualizerState: Binding<KeyboardShortcutVisualizerState> = .constant(.inactive),
            isInvalid: Bool = false,
            candidateIssueMessage: @escaping (HotkeyDescriptor) -> String? = { _ in nil },
            chipDisplayOverride: ((HotkeyDescriptor) -> String)? = nil
        ) {
            _descriptor = descriptor
            _visualizerState = visualizerState
            self.isInvalid = isInvalid
            self.candidateIssueMessage = candidateIssueMessage
            self.chipDisplayOverride = chipDisplayOverride
            super.init(frame: .zero)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            wantsLayer = true
            layer?.borderWidth = 1
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Shortcut recorder")
            setLabelText(chipText(for: descriptor.wrappedValue))
            updateAppearance()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func layout() {
            super.layout()
            let labelBounds = bounds.insetBy(dx: 8, dy: 0)
            let labelHeight = min(label.intrinsicContentSize.height, labelBounds.height)
            label.frame = NSRect(
                x: labelBounds.minX,
                y: labelBounds.midY - labelHeight / 2,
                width: labelBounds.width,
                height: labelHeight
            )
        }

        override func mouseDown(with event: NSEvent) {
            startRecording(ignoreInitialKeyEvents: false)
        }

        override func accessibilityPerformPress() -> Bool {
            startRecording(ignoreInitialKeyEvents: true)
            return true
        }

        override func becomeFirstResponder() -> Bool {
            return true
        }

        override func resignFirstResponder() -> Bool {
            return true
        }

        override func keyDown(with event: NSEvent) {
            capture(event)
        }

        override func flagsChanged(with event: NSEvent) {
            updateActiveModifiers(event.modifierFlags)
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateAppearance()
        }

        deinit {
            MainActor.assumeIsolated { floatingKeyboard.dismiss(immediate: true) }
            stopMonitoringKeyboard()
        }

        func updateDescriptorBinding(_ descriptor: Binding<HotkeyDescriptor>) {
            _descriptor = descriptor
            refresh()
        }

        func updateVisualizerStateBinding(_ visualizerState: Binding<KeyboardShortcutVisualizerState>) {
            _visualizerState = visualizerState
        }

        func updateValidationState(isInvalid: Bool) {
            self.isInvalid = isInvalid
            updateAppearance()
        }

        func updateCandidateIssueMessage(_ candidateIssueMessage: @escaping (HotkeyDescriptor) -> String?) {
            self.candidateIssueMessage = candidateIssueMessage
            if let pendingDescriptor {
                pendingIssueMessage = candidateIssueMessage(pendingDescriptor)
                refreshFloatingKeyboard()
            }
        }

        func updateChipDisplayOverride(_ override: ((HotkeyDescriptor) -> String)?) {
            self.chipDisplayOverride = override
            if !isRecording { setLabelText(chipText(for: descriptor)) }
        }

        private func chipText(for descriptor: HotkeyDescriptor) -> String {
            if let override = chipDisplayOverride {
                return HotkeyChipPresentation.displayText(override(descriptor))
            }
            return HotkeyChipPresentation.displayText(descriptor.display)
        }

        func refresh() {
            if !isRecording {
                setLabelText(chipText(for: descriptor))
            }
            updateAppearance()
        }

        private func startRecording(ignoreInitialKeyEvents: Bool) {
            guard !isRecording else { return }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            activeModifierFlags = []
            pendingDescriptor = nil
            pendingIssueMessage = nil
            ignoreKeyEventsUntil = ignoreInitialKeyEvents ? ProcessInfo.processInfo.systemUptime + 0.15 : 0
            resetTapState()
            isRecording = true
            publishVisualizerState(.recording())
            setLabelText("Press shortcut...")
            startMonitoringKeyboard()
            NotificationCenter.default.post(name: .hotkeyRecorderDidStartRecording, object: self)
            updateAppearance()
        }

        private func stopRecording() {
            guard isRecording else { return }
            isRecording = false
            activeModifierFlags = []
            pendingDescriptor = nil
            pendingIssueMessage = nil
            ignoreKeyEventsUntil = 0
            resetTapState()
            publishVisualizerState(.inactive)
            stopMonitoringKeyboard()
            NotificationCenter.default.post(name: .hotkeyRecorderDidStopRecording, object: self)
            refresh()
        }

        private func capture(_ event: NSEvent) {
            guard isRecording else { return }
            let eventTime = event.timestamp > 0 ? event.timestamp : ProcessInfo.processInfo.systemUptime
            guard eventTime >= ignoreKeyEventsUntil else { return }
            if event.keyCode == 53 {
                stopRecording()
                return
            }
            // A real key is being pressed — cancel any pending tap candidate.
            tapNonModifierPressed = true
            if pendingDescriptor?.isModifierTap == true {
                pendingDescriptor = nil
                pendingIssueMessage = nil
            }
            if Self.isConfirmKey(event.keyCode), pendingDescriptor != nil {
                confirmPendingShortcut()
                return
            }
            let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let captureFlags = eventFlags.isEmpty ? activeModifierFlags : eventFlags
            let raw = UInt32(captureFlags.rawValue)
            var mods: HotkeyDescriptor.Modifiers = []
            if raw & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { mods.insert(.command) }
            if raw & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { mods.insert(.option) }
            if raw & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { mods.insert(.control) }
            if raw & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { mods.insert(.shift) }
            previewCandidate(
                HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: mods),
                state: .recording(keyCode: event.keyCode, modifierFlags: captureFlags)
            )
        }

        private func capture(keyCode: UInt16, cgFlags: CGEventFlags) {
            guard isRecording else { return }
            guard ProcessInfo.processInfo.systemUptime >= ignoreKeyEventsUntil else { return }
            if keyCode == 53 {
                stopRecording()
                return
            }
            // A real key is being pressed — cancel any pending tap candidate.
            tapNonModifierPressed = true
            if pendingDescriptor?.isModifierTap == true {
                pendingDescriptor = nil
                pendingIssueMessage = nil
            }
            if Self.isConfirmKey(keyCode), pendingDescriptor != nil {
                confirmPendingShortcut()
                return
            }
            previewCandidate(
                HotkeyRecorderEventTranslator.descriptor(
                    keyCode: keyCode,
                    cgFlags: cgFlags,
                    fallbackModifierFlags: activeModifierFlags
                ),
                state: .recording(keyCode: keyCode, cgFlags: cgFlags)
            )
        }

        func confirmPendingShortcut() {
            guard isRecording, let pendingDescriptor else { return }
            pendingIssueMessage = candidateIssueMessage(pendingDescriptor)
            refreshFloatingKeyboard()
            guard pendingIssueMessage == nil else {
                updateAppearance()
                return
            }

            descriptor = pendingDescriptor
            stopRecording()
        }

        func resetPendingShortcut() {
            guard isRecording else { return }
            activeModifierFlags = []
            pendingDescriptor = nil
            pendingIssueMessage = nil
            publishVisualizerState(.recording())
            setLabelText("Press shortcut...")
            updateAppearance()
        }

        private func previewCandidate(_ candidate: HotkeyDescriptor, state: KeyboardShortcutVisualizerState) {
            pendingDescriptor = candidate
            pendingIssueMessage = candidateIssueMessage(candidate)
            publishVisualizerState(state)
            setLabelText(chipText(for: candidate))
            updateAppearance()
        }

        private func updateActiveModifiers(_ flags: NSEvent.ModifierFlags) {
            let cgFlags = Self.cgFlags(from: flags)
            activeModifierFlags = HotkeyRecorderEventTranslator.modifierFlags(from: cgFlags)
            guard isRecording else { return }
            // When the CGEventTap is active it owns tap detection; avoid double-firing.
            if tapController == nil {
                handleTapTransition(cgFlags: cgFlags)
            }

            let recorderState = KeyboardShortcutVisualizerState.recording(cgFlags: cgFlags)
            visualizerState = recorderState
            floatingKeyboard.update(
                state: recorderState,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingDescriptor?.isModifierTap == true ? nil : pendingIssueMessage,
                onReset: { [weak self] in self?.resetPendingShortcut() },
                onConfirm: { [weak self] in self?.confirmPendingShortcut() },
                onCancel: { [weak self] in self?.stopRecording() }
            )

            guard pendingDescriptor == nil else { return }

            let modifiers = modifierDisplay(from: activeModifierFlags)
            setLabelText(modifiers.isEmpty ? "Press shortcut..." : "\(modifiers)…")
        }

        private static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
            var result: CGEventFlags = []
            if flags.contains(.command) { result.insert(.maskCommand) }
            if flags.contains(.option) { result.insert(.maskAlternate) }
            if flags.contains(.control) { result.insert(.maskControl) }
            if flags.contains(.shift) { result.insert(.maskShift) }
            if flags.contains(.function) { result.insert(.maskSecondaryFn) }
            return result
        }

        private func updateActiveModifiers(cgFlags: CGEventFlags) {
            activeModifierFlags = HotkeyRecorderEventTranslator.modifierFlags(from: cgFlags)
            guard isRecording else { return }

            // All tap-candidate state lives inside handleTapTransition —
            // single source of truth for both press-replace, multi-tap, and
            // multi-modifier-cancel. No clear logic here.
            handleTapTransition(cgFlags: cgFlags)

            // Refresh keyboard with current modifier state (always, so the
            // keyboard highlights the held keys live).
            let recorderState = KeyboardShortcutVisualizerState.recording(cgFlags: cgFlags)
            visualizerState = recorderState
            floatingKeyboard.update(
                state: recorderState,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingDescriptor?.isModifierTap == true ? nil : pendingIssueMessage,
                onReset: { [weak self] in self?.resetPendingShortcut() },
                onConfirm: { [weak self] in self?.confirmPendingShortcut() },
                onCancel: { [weak self] in self?.stopRecording() }
            )

            guard pendingDescriptor == nil else { return }

            let modifiers = modifierDisplay(from: activeModifierFlags)
            setLabelText(modifiers.isEmpty ? "Press shortcut..." : "\(modifiers)…")
        }

        private func publishVisualizerState(_ state: KeyboardShortcutVisualizerState) {
            visualizerState = state
            floatingKeyboard.update(
                state: state,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingIssueMessage,
                onReset: { [weak self] in
                    self?.resetPendingShortcut()
                },
                onConfirm: { [weak self] in
                    self?.confirmPendingShortcut()
                },
                onCancel: { [weak self] in
                    self?.stopRecording()
                }
            )
        }

        private func refreshFloatingKeyboard() {
            floatingKeyboard.update(
                state: visualizerState,
                candidate: pendingDescriptor ?? Self.placeholderCandidate,
                issueMessage: pendingIssueMessage,
                onReset: { [weak self] in
                    self?.resetPendingShortcut()
                },
                onConfirm: { [weak self] in
                    self?.confirmPendingShortcut()
                },
                onCancel: { [weak self] in
                    self?.stopRecording()
                }
            )
        }

        private func modifierDisplay(from flags: NSEvent.ModifierFlags) -> String {
            var s = ""
            if flags.contains(.control) { s += "⌃" }
            if flags.contains(.option) { s += "⌥" }
            if flags.contains(.shift) { s += "⇧" }
            if flags.contains(.command) { s += "⌘" }
            return s
        }

        private static func isConfirmKey(_ keyCode: UInt16) -> Bool {
            Int(keyCode) == kVK_Return || Int(keyCode) == kVK_ANSI_KeypadEnter
        }

        /// Placeholder candidate used to keep the Confirm / Reset / Cancel
        /// button row visible in the floating keyboard even before the user
        /// has held a valid shortcut. Clicking Confirm with this placeholder
        /// is a safe no-op because `confirmPendingShortcut` guards on the
        /// real `pendingDescriptor`.
        private static let placeholderCandidate = HotkeyDescriptor(keyCode: 0, modifiers: [])

        // MARK: - Modifier-tap detection
        //
        // Single algorithm shared by every shortcut recorder in the app:
        //   - Press one modifier alone        → candidate = Tap <that modifier>
        //   - Hold / release that modifier    → candidate unchanged
        //   - Press a different modifier      → candidate replaced with the new one
        //   - Press a non-modifier key (combo)→ combo capture path replaces candidate
        //   - Press same modifier twice fast  → candidate upgrades to ×2
        //   - Two modifier families held      → tap candidate cleared (combo in flight)

        private func handleTapTransition(cgFlags: CGEventFlags) {
            let now = ProcessInfo.processInfo.systemUptime
            let held = !activeModifierFlags.isEmpty

            if held {
                if let key = tapKeyFromCGFlags(cgFlags) {
                    // Exactly one modifier family is held — this is a tap candidate.
                    let isFirstPressTransition = tapPressTime == nil
                    if isFirstPressTransition {
                        tapPressTime = now
                        tapNonModifierPressed = false
                    }
                    tapPressCGFlags = cgFlags

                    // Only set the candidate on the first press transition.
                    // Re-firing on every flagsChanged would reset count and
                    // overwrite a multi-tap upgrade.
                    if isFirstPressTransition {
                        let count: Int
                        if let last = tapLastRelease,
                           last.key == key,
                           now - last.time <= Self.multiTapWindow {
                            count = min(last.count + 1, 2)
                        } else {
                            count = 1
                        }
                        let tapDescriptor = HotkeyDescriptor(
                            modifierTap: ModifierTapShortcut(key: key, count: count)
                        )
                        previewCandidate(
                            tapDescriptor,
                            state: .recording(modifierFlags: activeModifierFlags)
                        )
                    }
                } else {
                    // Two or more modifier families held simultaneously — the
                    // user is mid-combo, not picking a single tap modifier.
                    tapPressCGFlags = cgFlags
                    if pendingDescriptor?.isModifierTap == true {
                        pendingDescriptor = nil
                        pendingIssueMessage = nil
                    }
                }
            } else if tapPressTime != nil {
                // All modifiers released. Record for multi-tap detection.
                // Candidate stays unchanged so the user sees what they picked.
                tapPressTime = nil
                if tapNonModifierPressed {
                    tapNonModifierPressed = false
                    tapLastRelease = nil
                    return
                }
                tapNonModifierPressed = false
                if let tap = pendingDescriptor?.modifierTap {
                    tapLastRelease = (key: tap.key, time: now, count: tap.count)
                }
            }
        }

        /// Test hook: apply modifier-tap detection without requiring a live CGEventTap.
        func testApplyCGFlags(_ cgFlags: CGEventFlags) {
            guard isRecording else { return }
            updateActiveModifiers(cgFlags: cgFlags)
        }

        func tapKeyFromCGFlags(_ cgFlags: CGEventFlags) -> ModifierTapShortcut.Key? {
            let raw = cgFlags.rawValue
            let lCtrl  = raw & CGModifierDeviceBit.leftControl != 0
            let lShift = raw & CGModifierDeviceBit.leftShift != 0
            let rShift = raw & CGModifierDeviceBit.rightShift != 0
            let lCmd   = raw & CGModifierDeviceBit.leftCommand != 0
            let rCmd   = raw & CGModifierDeviceBit.rightCommand != 0
            let lOpt   = raw & CGModifierDeviceBit.leftOption != 0
            let rOpt   = raw & CGModifierDeviceBit.rightOption != 0
            let rCtrl  = raw & CGModifierDeviceBit.rightControl != 0
            var families = 0
            var result: ModifierTapShortcut.Key?
            if lCtrl || rCtrl || cgFlags.contains(.maskControl) {
                families += 1
                result = lCtrl && !rCtrl ? .leftControl : rCtrl && !lCtrl ? .rightControl : .control
            }
            if lOpt || rOpt || cgFlags.contains(.maskAlternate) {
                families += 1
                result = lOpt && !rOpt ? .leftOption : rOpt && !lOpt ? .rightOption : .option
            }
            if lCmd || rCmd || cgFlags.contains(.maskCommand) {
                families += 1
                result = lCmd && !rCmd ? .leftCommand : rCmd && !lCmd ? .rightCommand : .command
            }
            if lShift || rShift || cgFlags.contains(.maskShift) {
                families += 1
                result = lShift && !rShift ? .leftShift : rShift && !lShift ? .rightShift : .shift
            }
            if cgFlags.contains(.maskSecondaryFn) { families += 1; result = .fn }
            return families == 1 ? result : nil
        }

        private func resetTapState() {
            tapPressTime = nil
            tapPressCGFlags = []
            tapNonModifierPressed = false
            tapLastRelease = nil
        }

        private func startMonitoringKeyboard() {
            guard keyMonitor == nil else { return }
            startKeyboardEventTap()
            keyMonitor = NSEventMonitorHandle(local: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }
                if event.type == .leftMouseDown {
                    return event
                }
                if event.type == .flagsChanged {
                    self.updateActiveModifiers(event.modifierFlags)
                    return nil
                }
                self.capture(event)
                return nil
            }
            globalKeyMonitor = NSEventMonitorHandle(global: [.keyDown, .flagsChanged]) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.isRecording else { return }
                    if event.type == .flagsChanged {
                        self.updateActiveModifiers(event.modifierFlags)
                    } else {
                        self.capture(event)
                    }
                }
            }
        }

        private func stopMonitoringKeyboard() {
            stopKeyboardEventTap()
            keyMonitor = nil
            globalKeyMonitor = nil
        }

        private func startKeyboardEventTap() {
            guard tapController == nil else { return }
            let mask = CGEventMask(
                (1 << CGEventType.keyDown.rawValue)
                    | (1 << CGEventType.flagsChanged.rawValue)
                    | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                    | (1 << CGEventType.tapDisabledByUserInput.rawValue)
            )
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            let controller = CGEventTapController(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                runLoop: .main,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let recorder = Unmanaged<RecorderView>.fromOpaque(userInfo).takeUnretainedValue()
                    return recorder.handleKeyboardEventTap(type: type, event: event)
                },
                userInfo: userInfo
            )
            do {
                try controller.install()
            } catch {
                return
            }
            controller.enable()
            tapController = controller
        }

        private func stopKeyboardEventTap() {
            tapController?.uninstall()
            tapController = nil
        }

        private func handleKeyboardEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                tapController?.reenableAfterTimeout()
                return Unmanaged.passUnretained(event)
            }

            guard isRecording else {
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .flagsChanged:
                updateActiveModifiers(cgFlags: event.flags)
                return nil
            case .keyDown:
                capture(
                    keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                    cgFlags: event.flags
                )
                return nil
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        private func updateAppearance() {
            layer?.cornerRadius = HotkeyChipPresentation.cornerRadius
            layer?.backgroundColor = resolvedColor(.textBackgroundColor)
            if isInvalid {
                layer?.borderColor = resolvedColor(.systemRed)
            } else if isRecording {
                layer?.borderColor = neutralLayerColor(alpha: 0.34)
            } else {
                layer?.borderColor = neutralLayerColor(alpha: 0.14)
                setLabelText(chipText(for: descriptor))
            }
        }

        private func setLabelText(_ text: String) {
            label.attributedStringValue = HotkeyChipPresentation.attributedString(
                text,
                color: isRecording ? .labelColor : .labelColor,
                compact: bounds.height <= HotkeyChipPresentation.compactHeight
            )
            needsLayout = true
        }

        private func resolvedColor(_ color: NSColor) -> CGColor {
            var result: CGColor = NSColor(calibratedRed: 1, green: 0.25, blue: 0.22, alpha: 1).cgColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                result = color.usingColorSpace(.deviceRGB)?.cgColor ?? result
            }
            return result
        }

        private func neutralLayerColor(alpha: CGFloat) -> CGColor {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 1 : 0, alpha: alpha).cgColor
        }
    }
}

enum HotkeyRecorderEventTranslator {
    static func descriptor(
        keyCode: UInt16,
        cgFlags: CGEventFlags,
        fallbackModifierFlags: NSEvent.ModifierFlags
    ) -> HotkeyDescriptor {
        let modifierFlags = modifierFlags(from: cgFlags)
        let captureFlags = modifierFlags.isEmpty ? fallbackModifierFlags : modifierFlags
        return HotkeyDescriptor(
            keyCode: UInt32(keyCode),
            modifiers: modifiers(from: captureFlags)
        )
    }

    static func modifierFlags(from cgFlags: CGEventFlags) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        return flags
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyDescriptor.Modifiers {
        var modifiers: HotkeyDescriptor.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
