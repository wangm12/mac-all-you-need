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
        private var isRecording = false

        init(binding: Binding<ShortcutBinding?>, onCapture: @escaping (ShortcutBinding) -> Void) {
            _binding = binding
            self.onCapture = onCapture
            super.init(frame: .zero)

            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            setLabelText(binding.wrappedValue?.display() ?? "Click to record")
            addSubview(label)

            wantsLayer = true
            layer?.borderWidth = 1
            updateAppearance()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func layout() {
            super.layout()
            label.frame = bounds.insetBy(dx: 8, dy: 0)
        }

        override func mouseDown(with event: NSEvent) {
            isRecording = true
            window?.makeFirstResponder(self)
            setLabelText("Press shortcut...")
            updateAppearance()
        }

        override func keyDown(with event: NSEvent) {
            let mask = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
            let mods = event.modifierFlags.rawValue & mask
            let captured = ShortcutBinding(keyCode: event.keyCode, modifierMask: mods)
            binding = captured
            isRecording = false
            setLabelText(captured.display())
            updateAppearance()
            onCapture(captured)
        }

        func refresh() {
            guard !isRecording else { return }
            setLabelText(binding?.display() ?? "Click to record")
            updateAppearance()
        }

        private func updateAppearance() {
            layer?.cornerRadius = HotkeyChipPresentation.cornerRadius
            layer?.backgroundColor = neutralLayerColor(alpha: isRecording ? 0.10 : 0.075)
            layer?.borderColor = neutralLayerColor(alpha: isRecording ? 0.55 : 0.16)
        }

        private func setLabelText(_ text: String) {
            label.attributedStringValue = HotkeyChipPresentation.attributedString(
                text,
                color: .labelColor,
                compact: true
            )
        }

        private func neutralLayerColor(alpha: CGFloat) -> CGColor {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedWhite: isDark ? 1 : 0, alpha: alpha).cgColor
        }
    }
}
