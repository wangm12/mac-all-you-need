import AppKit
import SwiftUI

@MainActor
final class WindowHubPanelController: NSWindowController {
    private let coordinator: WindowHubCoordinator
    private var escMonitor: Any?

    init(coordinator: WindowHubCoordinator) {
        self.coordinator = coordinator
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 660),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: 864, height: 460)
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: WindowHubOverlayView(coordinator: coordinator))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let panel = window as? NSPanel else { return }
        coordinator.openPanel()
        panel.makeKeyAndOrderFront(nil)
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
    }

    func dismiss() {
        removeEscMonitor()
        coordinator.closePanel()
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let frame = panel.frame
        let x = visible.minX + (visible.width - frame.width) / 2
        let y = visible.minY + (visible.height - frame.height) / 2
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}
