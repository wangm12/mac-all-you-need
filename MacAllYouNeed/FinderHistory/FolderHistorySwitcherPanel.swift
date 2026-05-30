import AppKit
import Core
import SwiftUI

/// Borderless floating panel hosting the folder-history quick switcher.
/// Becomes key so the search field is focused immediately; dismissed on Esc,
/// on focus loss, or after a selection. Arrow keys / Return are routed through
/// a local key monitor into the SwiftUI view.
@MainActor
final class FolderHistorySwitcherPanel {
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private let store: FolderHistoryStore
    private var viewModel = ViewBox()

    init(store: FolderHistoryStore) {
        self.store = store
    }

    /// A reference box so the local key monitor can forward to the live view.
    private final class ViewBox {
        var move: ((Int) -> Void)?
        var open: (() -> Void)?
    }

    func toggle() {
        if panel != nil {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        dismiss()

        let box = viewModel
        let view = FolderHistorySwitcherView(
            store: store,
            onSelect: { [weak self] row in
                FolderHistoryActions.open(path: row.path)
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)
        // Capture nav hooks from a fresh value-type copy is not possible; instead the
        // monitor drives navigation by re-reading the hosting view's root view.
        box.move = { [weak hosting] delta in hosting?.rootView.move(by: delta) }
        box.open = { [weak hosting] in hosting?.rootView.openHighlighted() }

        let size = hosting.fittingSize
        let origin = centeredOrigin(for: size)
        let p = KeyablePanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p

        installKeyMonitor(box: box)
    }

    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func centeredOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.midX - size.width / 2
        let y = screen.midY - size.height / 2 + screen.height * 0.1
        return NSPoint(x: x, y: y)
    }

    private func installKeyMonitor(box: ViewBox) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            switch event.keyCode {
            case 53: // Esc
                self.dismiss()
                return nil
            case 125: // Down arrow
                box.move?(1)
                return nil
            case 126: // Up arrow
                box.move?(-1)
                return nil
            case 36, 76: // Return / numpad Enter
                box.open?()
                return nil
            default:
                return event
            }
        }
    }
}

/// Borderless panels cannot become key by default; this subclass opts in so the
/// embedded search field receives keystrokes.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
