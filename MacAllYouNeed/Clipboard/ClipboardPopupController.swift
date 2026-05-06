import AppKit
import SwiftUI

final class ClipboardPopupController {
    private var window: NSPanel?
    let deps: AppDependencies

    init(deps: AppDependencies) { self.deps = deps }

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
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
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
    }

    @MainActor
    func hide() { window?.orderOut(nil) }
}
