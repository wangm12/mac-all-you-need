import AppKit
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var binding: ShortcutBinding?
    let onCapture: (ShortcutBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(binding: $binding, onCapture: onCapture)
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.refresh()
    }

    final class RecorderView: NSView {
        @Binding var binding: ShortcutBinding?
        let onCapture: (ShortcutBinding) -> Void
        private let label = NSTextField(labelWithString: "")

        init(binding: Binding<ShortcutBinding?>, onCapture: @escaping (ShortcutBinding) -> Void) {
            _binding = binding
            self.onCapture = onCapture
            super.init(frame: .zero)

            label.stringValue = binding.wrappedValue?.display() ?? "Click to record"
            addSubview(label)
            label.frame = NSRect(x: 4, y: 2, width: 120, height: 18)

            wantsLayer = true
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.cornerRadius = 4
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
            let mods = event.modifierFlags.rawValue & mask
            let captured = ShortcutBinding(keyCode: event.keyCode, modifierMask: mods)
            binding = captured
            label.stringValue = captured.display()
            onCapture(captured)
        }

        func refresh() {
            label.stringValue = binding?.display() ?? "Click to record"
        }
    }
}
