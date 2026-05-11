import AppKit
import Core
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
    private var spaceChangeObserver: NSObjectProtocol?
    private var pasteIntentObserver: NSObjectProtocol?
    private var hideRequestObserver: NSObjectProtocol?
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
        // Capture the user's app FIRST — before any activation our own panel
        // would do — so right-click "Paste to <App>" knows the target.
        model.previousFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Newest item should always be focused when the dock opens fresh.
        // Mid-session refreshes preserve focus via performRefresh's previousID
        // logic; we only override here on the user-initiated open.
        model.focusedIndex = 0
        Task { await model.refresh() }

        guard let screen = screenWithCursor() ?? NSScreen.main else { return }
        // Use the screen's full frame (not visibleFrame) so the dock sits flush
        // against the bottom edge of the display. visibleFrame would leave a
        // gap above the macOS Dock.
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: dockHeight
        )

        let log = Logging.logger(for: "dock", category: "window")
        log.info("show: cursor=\(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public), screen.frame=\(NSStringFromRect(screen.frame), privacy: .public), screen.visibleFrame=\(NSStringFromRect(screen.visibleFrame), privacy: .public), targetFrame=\(NSStringFromRect(frame), privacy: .public), screens.count=\(NSScreen.screens.count)")
        for (i, s) in NSScreen.screens.enumerated() {
            log.info("  screen[\(i)] frame=\(NSStringFromRect(s.frame), privacy: .public) visibleFrame=\(NSStringFromRect(s.visibleFrame), privacy: .public)")
        }

        // Always build a fresh panel. Reusing a cached BottomDockWindow across
        // screens caused DockAnimator.slideUp to read the old window.frame
        // (still in the prior screen's coordinate space) and compute a slide-
        // from origin that placed the panel off the laptop screen when the
        // first ⌘⇧V had been on the external monitor.
        let panel = BottomDockWindow(contentRect: frame)
        panel.setFrame(frame, display: false)
        let hosting = NSHostingView(
            rootView: DockRootView(
                model: model,
                favicons: favicons,
                registry: registry,
                dismiss: { [weak self] in
                    self?.hide()
                },
                onPaste: { [weak self] idx, modifiers in
                    self?.triggerPaste(at: idx, modifiers: modifiers)
                }
            )
        )
        // NSHostingView assigned as a panel's contentView does not auto-size
        // to the panel's content rect — without an explicit frame +
        // autoresizing mask, SwiftUI's outer VStack shrinks to the top bar
        // alone (~52px) and the carousel is invisible. Match the bounds and
        // let AppKit resize on subsequent setFrame calls.
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        window = panel

        panel.orderFrontRegardless()
        DockAnimator.slideUp(panel, finalOrigin: NSPoint(x: frame.minX, y: frame.minY)) { [weak panel, log] in
            panel?.makeKey()
            if let panel {
                log.info("show: post-animate panel.frame=\(NSStringFromRect(panel.frame), privacy: .public), panel.screen.frame=\(NSStringFromRect(panel.screen?.frame ?? .zero), privacy: .public)")
            }
        }

        startOutsideClickMonitor()
        startDragMonitor()
        startKeyMonitor()
        startSpaceChangeMonitor()
        startPasteIntentObserver()
        startHideRequestObserver()
    }

    func hide() {
        stopOutsideClickMonitor()
        stopDragMonitor()
        stopKeyMonitor()
        stopSpaceChangeMonitor()
        stopPasteIntentObserver()
        stopHideRequestObserver()
        guard let window else { return }
        DockAnimator.slideDown(window) { [weak self, weak window] in
            window?.orderOut(nil)
            // Drop the panel reference so the next show() builds a fresh one.
            // Required for multi-monitor: a cached panel slid up from the
            // wrong screen's coordinate space.
            self?.window = nil
        }
    }

    private func triggerPaste(at idx: Int, modifiers: EventModifiers) {
        guard model.items.indices.contains(idx) else { return }
        let id = model.items[idx].id

        // Use the modifier state captured at click time (passed in by the
        // carousel's TapGesture), not the current NSEvent.modifierFlags. By
        // the time SwiftUI dispatches the tap closure, the user may have
        // released ⌘ — reading global flags here silently degrades ⌘+click
        // into a destructive paste-and-dismiss.
        if modifiers.contains(.command) {
            model.toggleSelection(itemID: id)
            return
        }
        if modifiers.contains(.shift) {
            let anchor = model.focusedIndex
            let lower = min(anchor, idx)
            let upper = max(anchor, idx)
            for rangeIndex in lower...upper where model.items.indices.contains(rangeIndex) {
                model.selection.insert(model.items[rangeIndex].id)
            }
            model.focusedIndex = idx
            return
        }

        // ⌘1-9 / ⌘↩ / right-click "Paste to <App>" all reach here with empty
        // (or .option) modifiers and MUST paste regardless of any active
        // selection — single-click select happens in the carousel's tap
        // handler now and never reaches triggerPaste.
        let plainText = modifiers.contains(.option)
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

    /// Hide the dock as soon as the user switches to a different Space (3-finger
    /// swipe / Ctrl+arrow). The panel sets `.canJoinAllSpaces` so it remains
    /// visible mid-swipe (avoids a jarring mid-animation disappearance); this
    /// observer fires once the swipe lands so the dock is gone in the new
    /// Space's initial frame.
    private func startSpaceChangeMonitor() {
        stopSpaceChangeMonitor()
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func stopSpaceChangeMonitor() {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
            self.spaceChangeObserver = nil
        }
    }

    /// Listens for `dockPasteRequested` posted by `CardContextMenu`. Routes
    /// through `triggerPaste(at:modifiers:)` so dock-dismiss + 80 ms focus
    /// restore are reused.
    private func startPasteIntentObserver() {
        stopPasteIntentObserver()
        pasteIntentObserver = NotificationCenter.default.addObserver(
            forName: .dockPasteRequested, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let intent = note.object as? DockPasteIntent,
                  let idx = self.model.items.firstIndex(where: { $0.id == intent.itemID })
            else { return }
            self.triggerPaste(at: idx, modifiers: intent.plainText ? .option : [])
        }
    }

    private func stopPasteIntentObserver() {
        if let pasteIntentObserver {
            NotificationCenter.default.removeObserver(pasteIntentObserver)
            self.pasteIntentObserver = nil
        }
    }

    /// Listen for `dockHideRequested` from in-dock views (e.g. card double-
    /// click) and dismiss the panel. Skip if the panel is already hidden
    /// (avoids redundant slide-down on rapid double-clicks).
    private func startHideRequestObserver() {
        stopHideRequestObserver()
        hideRequestObserver = NotificationCenter.default.addObserver(
            forName: .dockHideRequested, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.hide()
        }
    }

    private func stopHideRequestObserver() {
        if let hideRequestObserver {
            NotificationCenter.default.removeObserver(hideRequestObserver)
            self.hideRequestObserver = nil
        }
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible else { return event }

            if registry.matches(event: event, .quickLook) {
                // Image / text cards open the floating PreviewPanel
                // (same behavior as the menu bar popover). Other kinds
                // fall back to the in-window QuickLookOverlay so the user
                // can still preview color / link / multi-file cards.
                if PreviewPanel.isVisible {
                    PreviewPanel.dismiss()
                } else if !showFloatingImagePreviewForFocused() {
                    model.isQuickLooking.toggle()
                }
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
                // Mirror the bar's Delete button — `deleteEffectiveTargets`
                // covers both multi-select and focused-only paths and runs
                // locally (no XPC dependency).
                Task { @MainActor in
                    await self.model.deleteEffectiveTargets()
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
                    triggerPaste(at: model.focusedIndex, modifiers: [])
                }
                return nil
            }

            if registry.matches(event: event, .pastePlain) {
                if !model.selection.isEmpty {
                    Task { @MainActor in
                        await self.model.pasteSelectionInOrder(delimiter: "\n", plainText: true)
                    }
                } else {
                    triggerPaste(at: model.focusedIndex, modifiers: .option)
                }
                return nil
            }

            if model.isQuickLooking || PreviewPanel.isVisible {
                if event.keyCode == 124 {
                    // Boundary no-op: at the rightmost card focusForward is
                    // a no-op on focusedIndex, but we'd still re-fire the
                    // preview show() and SwiftUI would briefly flash. Skip
                    // the re-show when focus didn't actually move.
                    let before = model.focusedIndex
                    model.focusForward()
                    if model.focusedIndex != before, PreviewPanel.isVisible {
                        showFloatingImagePreviewForFocused()
                    }
                    return nil
                }
                if event.keyCode == 123 {
                    let before = model.focusedIndex
                    model.focusBackward()
                    if model.focusedIndex != before, PreviewPanel.isVisible {
                        showFloatingImagePreviewForFocused()
                    }
                    return nil
                }
            }

            let keyMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // If the search field (or any text editor in the panel) has
            // focus, let macOS's native ⌘A/⌘C/⌘X/⌘V/⌘Z handlers do their
            // job — selecting all text, copying the search query, etc.
            // Without this guard our card-level ⌘C / ⌘A would steal the
            // event and the search field would feel broken.
            if keyMods == .command,
               isTextEditingFirstResponder(in: window),
               let char = event.charactersIgnoringModifiers?.lowercased(),
               ["a", "c", "x", "v", "z", "y"].contains(char)
            {
                return event
            }

            // ⌘1-⌘9 → paste the corresponding card (1-indexed). Each card
            // surfaces this shortcut in its bottom-left badge, so wiring the
            // handler here makes those badges actionable.
            if keyMods == .command,
               let chars = event.charactersIgnoringModifiers,
               chars.count == 1,
               let digit = chars.first?.wholeNumberValue,
               (1 ... 9).contains(digit)
            {
                let idx = digit - 1
                if model.items.indices.contains(idx) {
                    triggerPaste(at: idx, modifiers: [])
                }
                return nil
            }

            // ⌘C → mirror the bar's Copy button. Operates on the
            // multi-selection if any, otherwise the focused card.
            if keyMods == .command, event.charactersIgnoringModifiers == "c" {
                Task { @MainActor in
                    await self.model.copyEffectiveTargets(plainText: false)
                }
                return nil
            }

            // ⌘A → select every visible card (capped at 50 by selectAllVisible).
            if keyMods == .command, event.charactersIgnoringModifiers == "a" {
                model.selectAllVisible()
                return nil
            }

            if keyMods.isEmpty {
                switch event.keyCode {
                case 0x7B:
                    let before = model.focusedIndex
                    model.focusBackward()
                    if model.focusedIndex != before, PreviewPanel.isVisible {
                        showFloatingImagePreviewForFocused()
                    }
                    return nil
                case 0x7C:
                    let before = model.focusedIndex
                    model.focusForward()
                    if model.focusedIndex != before, PreviewPanel.isVisible {
                        showFloatingImagePreviewForFocused()
                    }
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

    /// True when the dock's key window has a text editor as its first
    /// responder (e.g. the search field). Used to skip our card-level
    /// ⌘A/⌘C/⌘X/⌘V handlers so the field gets native text-editing
    /// behavior. NSTextField uses a shared NSTextView "field editor" while
    /// editing, so we check both classes.
    private func isTextEditingFirstResponder(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSText { return true }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        return false
    }

    /// Open the floating `PreviewPanel` for the focused card. Returns true
    /// if a preview was shown — caller falls through to the in-window
    /// QuickLookOverlay if false (handled kinds: image, image file URL,
    /// text, html, rtf; falls through for color/link/multi-file).
    @discardableResult
    func showFloatingImagePreviewForFocused() -> Bool {
        guard model.items.indices.contains(model.focusedIndex),
              let clip = model.clip
        else { return false }
        let item = model.items[model.focusedIndex]
        guard let rid = Core.RecordID(rawValue: item.id),
              let body = try? clip.body(for: rid)
        else { return false }
        switch body {
        case let .image(blobID, _, _):
            guard let blobs = model.blobs,
                  let data = try? blobs.read(id: blobID),
                  let image = NSImage(data: data)
            else { return false }
            PreviewPanel.show(.image(image))
            return true
        case let .files(urls) where urls.count == 1 && Self.isImageURL(urls[0]):
            guard let image = NSImage(contentsOf: urls[0]) else { return false }
            PreviewPanel.show(.image(image))
            return true
        case let .text(s):
            PreviewPanel.show(.text(s, monospaced: false))
            return true
        case let .html(s):
            let plain = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            PreviewPanel.show(.text(plain, monospaced: false))
            return true
        case let .rtf(data):
            if let attr = NSAttributedString(rtf: data, documentAttributes: nil) {
                PreviewPanel.show(.text(attr.string, monospaced: false))
                return true
            }
            return false
        case .files:
            // Multi-file or non-image file — let the in-window overlay handle it.
            return false
        }
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"].contains(ext)
    }
}
