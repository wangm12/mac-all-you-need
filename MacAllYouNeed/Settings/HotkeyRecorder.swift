import AppKit
import CoreGraphics
import Platform
import SwiftUI

extension Notification.Name {
    static let hotkeyRecorderDidStartRecording = Notification.Name("MAYNHotkeyRecorderDidStartRecording")
    static let hotkeyRecorderDidStopRecording = Notification.Name("MAYNHotkeyRecorderDidStopRecording")
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var descriptor: HotkeyDescriptor
    var isInvalid = false

    func makeNSView(context: Context) -> RecorderView { RecorderView(descriptor: $descriptor, isInvalid: isInvalid) }
    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.updateDescriptorBinding($descriptor)
        nsView.updateValidationState(isInvalid: isInvalid)
    }

    final class RecorderView: NSView {
        @Binding var descriptor: HotkeyDescriptor
        private let label = NSTextField(labelWithString: "")
        private var isInvalid: Bool
        private var isRecording = false
        private var activeModifierFlags: NSEvent.ModifierFlags = []
        private var ignoreKeyEventsUntil: TimeInterval = 0
        private(set) var keyMonitor: Any?
        private var globalKeyMonitor: Any?
        private var eventTap: CFMachPort?
        private var eventTapSource: CFRunLoopSource?

        init(descriptor: Binding<HotkeyDescriptor>, isInvalid: Bool = false) {
            _descriptor = descriptor
            self.isInvalid = isInvalid
            super.init(frame: .zero)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            wantsLayer = true
            layer?.borderWidth = 1
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Shortcut recorder")
            setLabelText(descriptor.wrappedValue.display)
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
            stopMonitoringKeyboard()
        }

        func updateDescriptorBinding(_ descriptor: Binding<HotkeyDescriptor>) {
            _descriptor = descriptor
            refresh()
        }

        func updateValidationState(isInvalid: Bool) {
            self.isInvalid = isInvalid
            updateAppearance()
        }

        func refresh() {
            if !isRecording {
                setLabelText(descriptor.display)
            }
            updateAppearance()
        }

        private func startRecording(ignoreInitialKeyEvents: Bool) {
            guard !isRecording else { return }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            activeModifierFlags = []
            ignoreKeyEventsUntil = ignoreInitialKeyEvents ? ProcessInfo.processInfo.systemUptime + 0.15 : 0
            isRecording = true
            setLabelText("Press shortcut...")
            startMonitoringKeyboard()
            NotificationCenter.default.post(name: .hotkeyRecorderDidStartRecording, object: self)
            updateAppearance()
        }

        private func stopRecording() {
            guard isRecording else { return }
            isRecording = false
            activeModifierFlags = []
            ignoreKeyEventsUntil = 0
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
            let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let captureFlags = eventFlags.isEmpty ? activeModifierFlags : eventFlags
            let raw = UInt32(captureFlags.rawValue)
            var mods: HotkeyDescriptor.Modifiers = []
            if raw & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { mods.insert(.command) }
            if raw & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { mods.insert(.option) }
            if raw & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { mods.insert(.control) }
            if raw & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { mods.insert(.shift) }
            descriptor = HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: mods)
            stopRecording()
        }

        private func capture(keyCode: UInt16, cgFlags: CGEventFlags) {
            guard isRecording else { return }
            guard ProcessInfo.processInfo.systemUptime >= ignoreKeyEventsUntil else { return }
            if keyCode == 53 {
                stopRecording()
                return
            }
            descriptor = HotkeyRecorderEventTranslator.descriptor(
                keyCode: keyCode,
                cgFlags: cgFlags,
                fallbackModifierFlags: activeModifierFlags
            )
            stopRecording()
        }

        private func updateActiveModifiers(_ flags: NSEvent.ModifierFlags) {
            activeModifierFlags = flags.intersection(.deviceIndependentFlagsMask)
            guard isRecording else { return }
            let modifiers = modifierDisplay(from: activeModifierFlags)
            setLabelText(modifiers.isEmpty ? "Press shortcut..." : "\(modifiers)…")
        }

        private func modifierDisplay(from flags: NSEvent.ModifierFlags) -> String {
            var s = ""
            if flags.contains(.control) { s += "⌃" }
            if flags.contains(.option) { s += "⌥" }
            if flags.contains(.shift) { s += "⇧" }
            if flags.contains(.command) { s += "⌘" }
            return s
        }

        private func startMonitoringKeyboard() {
            guard keyMonitor == nil else { return }
            startKeyboardEventTap()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }
                if event.type == .leftMouseDown {
                    if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                        self.stopRecording()
                    }
                    return event
                }
                if event.type == .flagsChanged {
                    self.updateActiveModifiers(event.modifierFlags)
                    return nil
                }
                self.capture(event)
                return nil
            }
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
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
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let globalKeyMonitor {
                NSEvent.removeMonitor(globalKeyMonitor)
                self.globalKeyMonitor = nil
            }
        }

        private func startKeyboardEventTap() {
            guard eventTap == nil else { return }
            let mask = CGEventMask(
                (1 << CGEventType.keyDown.rawValue)
                    | (1 << CGEventType.flagsChanged.rawValue)
                    | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                    | (1 << CGEventType.tapDisabledByUserInput.rawValue)
            )
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let recorder = Unmanaged<RecorderView>.fromOpaque(userInfo).takeUnretainedValue()
                    return recorder.handleKeyboardEventTap(type: type, event: event)
                },
                userInfo: userInfo
            ) else {
                return
            }

            eventTap = tap
            eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let eventTapSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        private func stopKeyboardEventTap() {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            if let eventTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            }
            eventTapSource = nil
            eventTap = nil
        }

        private func handleKeyboardEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            guard isRecording else {
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .flagsChanged:
                updateActiveModifiers(HotkeyRecorderEventTranslator.modifierFlags(from: event.flags))
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
            let borderColor: NSColor
            if isInvalid {
                borderColor = .systemRed
            } else if isRecording {
                layer?.borderColor = neutralLayerColor(alpha: 0.34)
                setLabelText(label.stringValue)
                return
            } else {
                layer?.borderColor = neutralLayerColor(alpha: 0.14)
                setLabelText(label.stringValue)
                return
            }
            layer?.borderColor = resolvedColor(borderColor)
            setLabelText(label.stringValue)
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
            color.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor(calibratedRed: 1, green: 0.25, blue: 0.22, alpha: 1).cgColor
        }

        private func neutralLayerColor(alpha: CGFloat) -> CGColor {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 1 : 0, alpha: alpha).cgColor
        }
    }
}

enum HotkeyRecorderControlAxisAlignment: Equatable {
    case trailing
}

enum HotkeyRecorderErrorPlacement: Equatable {
    case belowControlsRightAligned
}

enum HotkeyRecorderResetState: Equatable {
    case active
    case inactive
}

struct HotkeyRecorderControlLayout: Equatable {
    let containerWidth: CGFloat
    let controlsAlignment: HotkeyRecorderControlAxisAlignment
    let errorPlacement: HotkeyRecorderErrorPlacement
}

enum HotkeyRecorderControlPresentation {
    static let defaultRecorderHeight = HotkeyChipPresentation.compactHeight

    static func layout(
        recorderWidth: CGFloat,
        resetWidth: CGFloat,
        spacing: CGFloat,
        errorWidth: CGFloat
    ) -> HotkeyRecorderControlLayout {
        HotkeyRecorderControlLayout(
            containerWidth: max(errorWidth, recorderWidth + spacing + resetWidth),
            controlsAlignment: .trailing,
            errorPlacement: .belowControlsRightAligned
        )
    }

    static func resetState(
        descriptor: HotkeyDescriptor,
        defaultDescriptor: HotkeyDescriptor?
    ) -> HotkeyRecorderResetState {
        guard let defaultDescriptor else { return .active }
        return descriptor == defaultDescriptor ? .inactive : .active
    }

    static func rowIssueMessage(
        validationIssue: String?,
        registrationErrors: [HotkeyAction: String],
        action: HotkeyAction
    ) -> String? {
        validationIssue ?? registrationErrors[action]
    }

    static func registrationErrors(
        from error: Error,
        changedAction: HotkeyAction
    ) -> [HotkeyAction: String] {
        if case let HotkeyRegistryError.registrationFailed(action, _) = error {
            return [action: error.localizedDescription]
        }
        return [changedAction: error.localizedDescription]
    }
}

struct HotkeyRecorderControl: View {
    @Binding var descriptor: HotkeyDescriptor
    var issueMessage: String?
    var defaultDescriptor: HotkeyDescriptor?
    var recorderWidth: CGFloat = 112
    var recorderHeight: CGFloat = HotkeyRecorderControlPresentation.defaultRecorderHeight
    var resetWidth: CGFloat = 64
    var errorWidth: CGFloat = 220
    var alignment: HorizontalAlignment = .trailing
    var errorFrameAlignment: Alignment = .trailing
    let reset: () -> Void

    var body: some View {
        let layout = HotkeyRecorderControlPresentation.layout(
            recorderWidth: recorderWidth,
            resetWidth: resetWidth,
            spacing: 8,
            errorWidth: errorWidth
        )
        let resetState = HotkeyRecorderControlPresentation.resetState(
            descriptor: descriptor,
            defaultDescriptor: defaultDescriptor
        )

        VStack(alignment: alignment, spacing: 5) {
            HStack(spacing: 8) {
                HotkeyRecorder(descriptor: $descriptor, isInvalid: issueMessage != nil)
                    .frame(width: recorderWidth, height: recorderHeight)
                Button(action: reset) {
                    Text("Reset")
                        .font(.callout.weight(resetState == .active ? .medium : .regular))
                        .foregroundStyle(resetState == .active ? .primary : .secondary)
                        .frame(width: resetWidth, height: recorderHeight)
                        .background(resetBackground(for: resetState), in: RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous)
                                .stroke(resetBorder(for: resetState), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(resetState == .inactive)
                .opacity(resetState == .active ? 1 : 0.62)
            }
            .frame(width: layout.containerWidth, alignment: .trailing)

            if let issueMessage {
                Text(issueMessage)
                    .font(.caption)
                    .foregroundStyle(MAYNTheme.danger)
                    .multilineTextAlignment(.trailing)
                    .frame(width: layout.containerWidth, alignment: errorFrameAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: layout.containerWidth, alignment: .trailing)
    }

    private func resetBackground(for state: HotkeyRecorderResetState) -> Color {
        switch state {
        case .active:
            MAYNTheme.elevated
        case .inactive:
            MAYNTheme.elevated
        }
    }

    private func resetBorder(for state: HotkeyRecorderResetState) -> Color {
        switch state {
        case .active:
            MAYNTheme.strongBorder
        case .inactive:
            .clear
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
