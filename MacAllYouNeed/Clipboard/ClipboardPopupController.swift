import AppKit
import SwiftUI

final class ClipboardPopupController {
    private var window: NSPanel?
    private var outsideClickMonitor: Any?
    let deps: AppDependencies

    init(deps: AppDependencies) {
        self.deps = deps
    }

    @MainActor
    func show() {
        Task { await deps.refresh() }
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 280),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.contentView = NSHostingView(
                rootView: ClipboardPopupView(deps: deps, dismiss: { [weak self] in self?.hide() })
            )
            window = panel
        }
        guard let window else { return }
        if let screen = NSScreen.main {
            let rect = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: rect.midX - frame.width / 2, y: rect.midY - frame.height / 2))
        }
        window.orderFrontRegardless()
        window.makeKey()
        startOutsideClickMonitor()
    }

    @MainActor
    func hide() {
        stopOutsideClickMonitor()
        window?.orderOut(nil)
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
