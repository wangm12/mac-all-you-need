import AppKit
import Foundation

@MainActor
final class ColorPickerCoordinator: NSObject, NSWindowDelegate {
    var onCommit: ((NSColor) -> Void)?

    private var latestColor: NSColor?
    private weak var observedPanel: NSColorPanel?

    func present(initial: NSColor) {
        let panel = NSColorPanel.shared
        observedPanel = panel
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        latestColor = sender.color
    }

    func windowWillClose(_ notification: Notification) {
        guard let color = latestColor else { return }
        onCommit?(color)
        latestColor = nil
        observedPanel?.delegate = nil
        observedPanel = nil
    }
}
