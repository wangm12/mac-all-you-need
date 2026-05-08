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
    private var dragMonitor: Any?
    private var ignoreOutsideClicksUntil: Date = .distantPast

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
        startDragMonitor()
        startKeyMonitor()
    }

    func hide() {
        stopOutsideClickMonitor()
        stopDragMonitor()
        stopKeyMonitor()
        guard let window else { return }
        DockAnimator.slideDown(window) { [weak window] in
            window?.orderOut(nil)
        }
    }

    private func triggerPaste(at idx: Int, plainText: Bool) {
        guard model.items.indices.contains(idx) else { return }
        let id = model.items[idx].id

        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            model.toggleSelection(itemID: id)
            return
        }
        if flags.contains(.shift) {
            let anchor = model.focusedIndex
            let lower = min(anchor, idx)
            let upper = max(anchor, idx)
            for rangeIndex in lower...upper where model.items.indices.contains(rangeIndex) {
                model.selection.insert(model.items[rangeIndex].id)
            }
            model.focusedIndex = idx
            return
        }
        if !model.selection.isEmpty {
            model.toggleSelection(itemID: id)
            return
        }

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
            guard let self else { return }
            if Date() < self.ignoreOutsideClicksUntil {
                return
            }
            Task { @MainActor in
                self.hide()
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

            if registry.matches(event: event, .quickLook) {
                model.isQuickLooking.toggle()
                return nil
            }

            if registry.matches(event: event, .toggleCheatsheet) {
                model.showCheatsheet.toggle()
                return nil
            }

            if registry.matches(event: event, .suspendCapture) {
                NotificationCenter.default.post(name: .pauseCaptureRequested, object: nil)
                return nil
            }

            if registry.matches(event: event, .transformFocused) {
                model.showTransformMenu = true
                return nil
            }

            if registry.matches(event: event, .extendSelectionRight) {
                model.extendSelectionRight()
                return nil
            }

            if registry.matches(event: event, .extendSelectionLeft) {
                model.extendSelectionLeft()
                return nil
            }

            if registry.matches(event: event, .deleteFocused) {
                Task { @MainActor in
                    if !self.model.selection.isEmpty {
                        await self.model.deleteSelected()
                    } else if self.model.items.indices.contains(self.model.focusedIndex) {
                        let focusedID = self.model.items[self.model.focusedIndex].id
                        _ = await self.model.xpc.deleteItem(id: focusedID)
                        await self.model.refresh()
                    }
                }
                return nil
            }

            if registry.matches(event: event, .dismiss) {
                if model.isQuickLooking {
                    model.isQuickLooking = false
                } else if model.showCheatsheet {
                    model.showCheatsheet = false
                } else if model.showTransformMenu {
                    model.showTransformMenu = false
                } else {
                    hide()
                }
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
                if !model.selection.isEmpty {
                    Task { @MainActor in
                        await self.model.pasteSelectionInOrder(delimiter: "\n", plainText: false)
                    }
                } else {
                    triggerPaste(at: model.focusedIndex, plainText: false)
                }
                return nil
            }

            if registry.matches(event: event, .pastePlain) {
                if !model.selection.isEmpty {
                    Task { @MainActor in
                        await self.model.pasteSelectionInOrder(delimiter: "\n", plainText: true)
                    }
                } else {
                    triggerPaste(at: model.focusedIndex, plainText: true)
                }
                return nil
            }

            if model.isQuickLooking {
                if event.keyCode == 124 {
                    model.focusForward()
                    return nil
                }
                if event.keyCode == 123 {
                    model.focusBackward()
                    return nil
                }
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

    private func startDragMonitor() {
        stopDragMonitor()
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isVisible,
                  let eventWindow = event.window,
                  eventWindow == window
            else {
                return event
            }

            self.ignoreOutsideClicksUntil = Date().addingTimeInterval(0.8)
            return event
        }
    }

    private func stopDragMonitor() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
