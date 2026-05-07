import AppKit
import Platform
import SwiftUI

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var descriptor: HotkeyDescriptor

    func makeNSView(context: Context) -> RecorderView { RecorderView(descriptor: $descriptor) }
    func updateNSView(_ nsView: RecorderView, context: Context) { nsView.refresh() }

    final class RecorderView: NSView {
        @Binding var descriptor: HotkeyDescriptor
        private let label = NSTextField(labelWithString: "")

        init(descriptor: Binding<HotkeyDescriptor>) {
            _descriptor = descriptor
            super.init(frame: .zero)
            label.stringValue = descriptor.wrappedValue.display
            addSubview(label)
            label.frame = NSRect(x: 4, y: 2, width: 90, height: 18)
            wantsLayer = true
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.cornerRadius = 4
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let raw = UInt32(event.modifierFlags.rawValue & UInt(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue))
            var mods: HotkeyDescriptor.Modifiers = []
            if raw & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { mods.insert(.command) }
            if raw & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { mods.insert(.option) }
            if raw & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { mods.insert(.control) }
            if raw & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { mods.insert(.shift) }
            descriptor = HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: mods)
            label.stringValue = descriptor.display
        }

        func refresh() { label.stringValue = descriptor.display }
    }
}
