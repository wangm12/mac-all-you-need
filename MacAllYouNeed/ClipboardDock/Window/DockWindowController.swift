import AppKit
import SwiftUI

@MainActor
final class DockWindowController {
    private let model: ClipboardDockModel
    private let pasteCoordinator: DockPasteCoordinator
    private let favicons: FaviconCache
    private let registry: ShortcutRegistry

    private var window: BottomDockWindow?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    var dockHeight: CGFloat = 360

    init(
        model: ClipboardDockModel,
        pasteCoordinator: DockPasteCoordinator,
        favicons: FaviconCache,
        registry: ShortcutRegistry
    ) {
        self.model = model
        self.pasteCoordinator = pasteCoordinator
        self.favicons = favicons
        self.registry = registry
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        Task { await model.refresh() }

        guard let screen = screenWithCursor() ?? NSScreen.main else { return }
        let frame = NSRect(
            x: screen.visibleFrame.minX,
            y: screen.visibleFrame.minY,
            width: screen.visibleFrame.width,
            height: dockHeight
        )

        let panel = window ?? BottomDockWindow(contentRect: frame)
        panel.setFrame(frame, display: false)
        panel.contentView = NSHostingView(
            rootView: DockRootView(
                model: model,
                favicons: favicons,
                registry: registry,
                dismiss: { [weak self] in
                    self?.hide()
                },
                onPaste: { [weak self] idx, plainText in
                    self?.triggerPaste(at: idx, plainText: plainText)
                },
                openSettings: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            )
        )

        if window == nil {
            window = panel
        }

        panel.orderFrontRegardless()
        DockAnimator.slideUp(panel, finalOrigin: NSPoint(x: frame.minX, y: frame.minY)) {
            panel.makeKey()
        }

        startOutsideClickMonitor()
        startKeyMonitor()
    }

    func hide() {
        stopOutsideClickMonitor()
        stopKeyMonitor()
        guard let window else { return }
        DockAnimator.slideDown(window) { [weak window] in
            window?.orderOut(nil)
        }
    }

    private func triggerPaste(at idx: Int, plainText: Bool) {
        guard model.items.indices.contains(idx) else { return }
        let id = model.items[idx].id
        Task { [weak self] in
            guard let self else { return }
            await self.pasteCoordinator.paste(
                itemID: id,
                plainText: plainText,
                dismissWindow: { self.hide() }
            )
        }
    }

    private func screenWithCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible else { return event }

            if registry.matches(event: event, .dismiss) {
                hide()
                return nil
            }

            if registry.matches(event: event, .togglePin) {
                Task { @MainActor in
                    guard self.model.items.indices.contains(self.model.focusedIndex) else { return }
                    let id = self.model.items[self.model.focusedIndex].id
                    await self.model.togglePin(itemID: id)
                }
                return nil
            }

            if registry.matches(event: event, .paste) {
                triggerPaste(at: model.focusedIndex, plainText: false)
                return nil
            }

            if registry.matches(event: event, .pastePlain) {
                triggerPaste(at: model.focusedIndex, plainText: true)
                return nil
            }

            let keyMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if keyMods.isEmpty {
                switch event.keyCode {
                case 0x7B:
                    model.focusBackward()
                    return nil
                case 0x7C:
                    model.focusForward()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
