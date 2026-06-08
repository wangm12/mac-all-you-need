import AppKit
import Core
import SwiftUI

/// Borderless floating panel for the Finder folder history list (global hotkey).
@MainActor
final class FolderHistorySwitcherPanel {
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private let store: FolderHistoryStore
    private let model = FolderHistorySwitcherModel()

    init(store: FolderHistoryStore) {
        self.store = store
    }

    func toggle(context: FolderHistoryPanelContext) {
        if panel != nil {
            dismiss()
        } else {
            show(context: context)
        }
    }

    func show(context: FolderHistoryPanelContext) {
        dismiss()

        model.reload(store: store)

        let view = FolderHistorySwitcherView(
            model: model,
            context: context,
            onSelect: { [weak self] row in
                FolderHistoryActions.open(path: row.path)
                self?.dismiss()
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let size = hosting.fittingSize
        let screen = FolderHistoryPanelPlacement.preferredScreen() ?? NSScreen.main
        let origin = screen.map { FolderHistoryPanelPlacement.origin(panelSize: size, on: $0) }
            ?? NSPoint(x: 0, y: 0)
        let p = KeyablePanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel = p

        installKeyMonitor()
    }

    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            let optionHeld = event.modifierFlags.contains(.option)
            switch event.keyCode {
            case 53: // Esc
                self.dismiss()
                return nil
            case 125: // Down
                self.model.move(by: 1)
                return nil
            case 126: // Up
                self.model.move(by: -1)
                return nil
            case 36, 76: // Return / numpad Enter
                let items = self.model.displayedRows
                guard !items.isEmpty else { return nil }
                let index = items.indices.contains(self.model.highlighted) ? self.model.highlighted : 0
                let row = items[index]
                if optionHeld {
                    FolderHistoryActions.reveal(path: row.path)
                } else {
                    FolderHistoryActions.open(path: row.path)
                }
                self.dismiss()
                return nil
            default:
                return event
            }
        }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
