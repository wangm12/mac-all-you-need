import AppKit
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

        init(descriptor: Binding<HotkeyDescriptor>, isInvalid: Bool = false) {
            _descriptor = descriptor
            self.isInvalid = isInvalid
            super.init(frame: .zero)
            label.stringValue = descriptor.wrappedValue.display
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            wantsLayer = true
            layer?.cornerRadius = 4
            layer?.borderWidth = 1
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Shortcut recorder")
            updateAppearance()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func layout() {
            super.layout()
            label.frame = bounds.insetBy(dx: 8, dy: 3)
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
                label.stringValue = descriptor.display
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
            label.stringValue = "Press shortcut..."
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

        private func updateActiveModifiers(_ flags: NSEvent.ModifierFlags) {
            activeModifierFlags = flags.intersection(.deviceIndependentFlagsMask)
            guard isRecording else { return }
            let modifiers = modifierDisplay(from: activeModifierFlags)
            label.stringValue = modifiers.isEmpty ? "Press shortcut..." : "\(modifiers)…"
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
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let globalKeyMonitor {
                NSEvent.removeMonitor(globalKeyMonitor)
                self.globalKeyMonitor = nil
            }
        }

        private func updateAppearance() {
            label.textColor = isRecording ? .labelColor : .secondaryLabelColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            let borderColor: NSColor
            if isInvalid {
                borderColor = .systemRed
            } else if isRecording {
                borderColor = NSColor.labelColor.withAlphaComponent(0.55)
            } else {
                borderColor = .separatorColor
            }
            layer?.borderColor = borderColor.cgColor
        }
    }
}
