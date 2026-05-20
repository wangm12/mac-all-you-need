import AppKit
import ApplicationServices
import Core
import SwiftUI

enum DockTypingSearch {
    static func updatedQuery(
        current: String,
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let textModifiers: NSEvent.ModifierFlags = [.shift, .capsLock]
        guard relevantModifiers.subtracting(textModifiers).isEmpty else { return nil }

        if keyCode == 51 {
            guard !current.isEmpty else { return nil }
            return String(current.dropLast())
        }

        guard let characters, !characters.isEmpty else { return nil }
        let blockedCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard characters.rangeOfCharacter(from: blockedCharacters) == nil else { return nil }
        return current + characters
    }
}

enum DockLocalKeyEventScope {
    static func shouldHandle(eventWindow: NSWindow?, dockWindow: NSWindow, keyWindow: NSWindow?) -> Bool {
        if let eventWindow {
            return eventWindow === dockWindow
        }
        return keyWindow === dockWindow
    }
}

enum DockOutsideClickPolicy {
    static func shouldHide(
        panelFrame: NSRect,
        clickLocationOnScreen: NSPoint,
        ignoreOutsideClicksUntil: Date,
        now: Date
    ) -> Bool {
        guard now >= ignoreOutsideClicksUntil else { return false }
        return !panelFrame.contains(clickLocationOnScreen)
    }

    static func screenLocation(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else {
            return NSEvent.mouseLocation
        }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }
}

enum DockHeightPreviewLayering {
    static func invokerLevel(above dockLevel: NSWindow.Level) -> NSWindow.Level {
        let draggingLevel = Int(CGWindowLevelForKey(.draggingWindow))
        let raisedLevel = min(dockLevel.rawValue + 1, draggingLevel - 1)
        return NSWindow.Level(rawValue: raisedLevel)
    }
}

enum DockGlobalKeyFallbackAction: Equatable {
    case quickLook
    case dismiss
    case focusBackward
    case focusForward
}

struct DockGlobalKeyFallbackBindings {
    let quickLook: [ShortcutBinding]
    let dismiss: [ShortcutBinding]
}

enum DockGlobalKeyFallbackPolicy {
    static func modifierMask(from flags: CGEventFlags) -> UInt {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskAlphaShift) { modifiers.insert(.capsLock) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
    }

    static func action(
        keyCode: UInt16,
        modifierMask: UInt,
        bindings: DockGlobalKeyFallbackBindings
    ) -> DockGlobalKeyFallbackAction? {
        if matches(bindings.quickLook, keyCode: keyCode, modifierMask: modifierMask) {
            return .quickLook
        }
        if matches(bindings.dismiss, keyCode: keyCode, modifierMask: modifierMask) {
            return .dismiss
        }

        guard modifierMask == 0 else { return nil }
        switch keyCode {
        case 123:
            return .focusBackward
        case 124:
            return .focusForward
        default:
            return nil
        }
    }

    private static func matches(
        _ bindings: [ShortcutBinding],
        keyCode: UInt16,
        modifierMask: UInt
    ) -> Bool {
        bindings.contains { binding in
            binding.keyCode == keyCode && binding.modifierMask == modifierMask
        }
    }
}

private final class DockGlobalKeyEventTap {
    private let bindings: DockGlobalKeyFallbackBindings
    private let handleAction: @MainActor (DockGlobalKeyFallbackAction) -> Void
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    init(
        bindings: DockGlobalKeyFallbackBindings,
        handleAction: @escaping @MainActor (DockGlobalKeyFallbackAction) -> Void
    ) {
        self.bindings = bindings
        self.handleAction = handleAction
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let eventTap = Unmanaged<DockGlobalKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return eventTap.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTapSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierMask = DockGlobalKeyFallbackPolicy.modifierMask(from: event.flags)
        guard let action = DockGlobalKeyFallbackPolicy.action(
            keyCode: keyCode,
            modifierMask: modifierMask,
            bindings: bindings
        ) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor [handleAction] in
            handleAction(action)
        }
        return nil
    }
}

@MainActor
final class DockWindowController {
    private let model: ClipboardDockModel
    private let pasteCoordinator: DockPasteCoordinator
    private let favicons: FaviconCache
    private let registry: ShortcutRegistry

    private var window: BottomDockWindow?
    private var globalOutsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalKeyEventTap: DockGlobalKeyEventTap?
    private var dragMonitor: Any?
    private var dragSurfaceClearTask: Task<Void, Never>?
    private var spaceChangeObserver: NSObjectProtocol?
    private var pasteIntentObserver: NSObjectProtocol?
    private var hideRequestObserver: NSObjectProtocol?
    private var ignoreOutsideClicksUntil: Date = .distantPast
    private weak var heightPreviewInvokerWindow: NSWindow?
    private var heightPreviewInvokerOriginalLevel: NSWindow.Level?

    var dockHeight: CGFloat = 360 {
        didSet {
            resizeVisiblePanelForCurrentHeight()
        }
    }

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

#if DEBUG
    var debugWindowForTesting: BottomDockWindow? { window }
    var debugHasGlobalOutsideClickMonitorForTesting: Bool { globalOutsideClickMonitor != nil }
    var debugHasLocalOutsideClickMonitorForTesting: Bool { localOutsideClickMonitor != nil }
    var debugHasGlobalKeyMonitorForTesting: Bool { globalKeyMonitor != nil }

    func debugSetWindowForTesting(_ window: BottomDockWindow?) {
        self.window = window
    }

    func debugTearDownForTesting() {
        restoreHeightPreviewInvokerWindowLevel()
        stopOutsideClickMonitor()
        stopDragMonitor()
        stopKeyMonitor()
        stopSpaceChangeMonitor()
        stopPasteIntentObserver()
        stopHideRequestObserver()
        window?.contentView?.layer?.removeAllAnimations()
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
#endif

    func show() {
        // Capture the user's app FIRST — before any activation our own panel
        // would do — so right-click "Paste to <App>" knows the target.
        model.previousFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let preserveFocusOnOpen = ClipboardDockOpenFocusSetting.load()
        // Default open behavior focuses the newest item. A clipboard setting
        // can opt back into preserving the previous focused card.
        if !preserveFocusOnOpen {
            model.focusedIndex = 0
        }
        Task {
            await model.refreshForDockOpen(
                preserveFocus: preserveFocusOnOpen
            )
        }

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

        if let panel = window, panel.isVisible {
            showExistingPanel(panel, frame: frame)
            log.info("show: reused visible panel.frame=\(NSStringFromRect(panel.frame), privacy: .public)")
            return
        }

        // Build a fresh panel when the dock is not currently visible. Reusing a
        // hidden cached BottomDockWindow across screens caused DockAnimator.slideUp
        // to read the old window.frame and compute a slide-from origin in the
        // prior screen's coordinate space.
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
        focusDockPanelForKeyboardInput(panel)
        raiseHeightPreviewInvokerAboveDockPanelIfNeeded()
        DockAnimator.slideUp(panel, finalOrigin: NSPoint(x: frame.minX, y: frame.minY)) { [weak self, weak panel, log] in
            if self?.heightPreviewInvokerWindow == nil {
                if let panel {
                    self?.focusDockPanelForKeyboardInput(panel)
                }
                self?.model.requestSearchFocus()
            } else {
                self?.raiseHeightPreviewInvokerAboveDockPanelIfNeeded()
            }
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

    func keepHeightPreviewInvokerAboveDockPanel(_ invokerWindow: NSWindow?) {
        guard window?.isVisible == true, let invokerWindow else { return }
        beginHeightPreviewLayering(invokerWindow: invokerWindow)
    }

    func endHeightPreviewLayering() {
        restoreHeightPreviewInvokerWindowLevel()
    }

    func previewHeight(_ height: CGFloat, keepingInvokerAbove invokerWindow: NSWindow? = nil) {
        if let invokerWindow {
            beginHeightPreviewLayering(invokerWindow: invokerWindow)
        }
        dockHeight = height
        if window?.isVisible != true {
            show()
        } else {
            raiseHeightPreviewInvokerAboveDockPanelIfNeeded()
        }
    }

    private func showExistingPanel(_ panel: BottomDockWindow, frame: NSRect) {
        panel.contentView?.layer?.removeAllAnimations()
        panel.alphaValue = 1
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.orderFrontRegardless()
        if heightPreviewInvokerWindow == nil {
            focusDockPanelForKeyboardInput(panel)
            model.requestSearchFocus()
        } else {
            raiseHeightPreviewInvokerAboveDockPanelIfNeeded()
        }

        startOutsideClickMonitor()
        startDragMonitor()
        startKeyMonitor()
        startSpaceChangeMonitor()
        startPasteIntentObserver()
        startHideRequestObserver()
    }

    private func resizeVisiblePanelForCurrentHeight() {
        guard let panel = window, panel.isVisible,
              let screen = panel.screen ?? screenWithCursor() ?? NSScreen.main
        else { return }

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: dockHeight
        )
        panel.contentView?.layer?.removeAllAnimations()
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        raiseHeightPreviewInvokerAboveDockPanelIfNeeded()
    }

    func hide() {
        PreviewPanel.dismiss()
        ClipboardSystemQuickLookCoordinator.shared.dismiss()
        model.isQuickLooking = false
        restoreHeightPreviewInvokerWindowLevel()
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

    private func beginHeightPreviewLayering(invokerWindow: NSWindow) {
        if heightPreviewInvokerWindow !== invokerWindow {
            restoreHeightPreviewInvokerWindowLevel()
            heightPreviewInvokerWindow = invokerWindow
            heightPreviewInvokerOriginalLevel = invokerWindow.level
        }
        raiseHeightPreviewInvokerAboveDockPanelIfNeeded()
    }

    private func raiseHeightPreviewInvokerAboveDockPanelIfNeeded() {
        guard let invokerWindow = heightPreviewInvokerWindow,
              let panel = window
        else { return }
        invokerWindow.level = DockHeightPreviewLayering.invokerLevel(above: panel.level)
        invokerWindow.orderFrontRegardless()
        invokerWindow.makeKey()
    }

    private func restoreHeightPreviewInvokerWindowLevel() {
        if let invokerWindow = heightPreviewInvokerWindow,
           let originalLevel = heightPreviewInvokerOriginalLevel
        {
            invokerWindow.level = originalLevel
        }
        heightPreviewInvokerWindow = nil
        heightPreviewInvokerOriginalLevel = nil
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
        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self, self.shouldHideForOutsideClick(event) else { return }
                self.hide()
            }
        }

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if self.shouldHideForOutsideClick(event) {
                self.hide()
            }
            return event
        }
    }

    private func stopOutsideClickMonitor() {
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
    }

    private func shouldHideForOutsideClick(_ event: NSEvent) -> Bool {
        guard let window, window.isVisible else { return false }
        return DockOutsideClickPolicy.shouldHide(
            panelFrame: window.frame,
            clickLocationOnScreen: DockOutsideClickPolicy.screenLocation(for: event),
            ignoreOutsideClicksUntil: ignoreOutsideClicksUntil,
            now: Date()
        )
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

    private func focusDockPanelForKeyboardInput(_ panel: BottomDockWindow) {
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible else { return event }
            guard DockLocalKeyEventScope.shouldHandle(
                eventWindow: event.window,
                dockWindow: window,
                keyWindow: NSApp.keyWindow
            ) else {
                return event
            }

            if registry.matches(event: event, .focusSearch) {
                model.requestSearchFocus()
                return nil
            }

            if registry.matches(event: event, .quickLook) {
                toggleSystemQuickLookForFocused()
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
                } else if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                    ClipboardSystemQuickLookCoordinator.shared.dismiss()
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
                if model.activeList == .snippets {
                    Task { @MainActor in
                        self.hide()
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        await self.model.pasteFocusedSnippet(plainText: false)
                    }
                } else if !model.selection.isEmpty {
                    Task { @MainActor in
                        await self.model.pasteSelectionInOrder(delimiter: "\n", plainText: false)
                    }
                } else {
                    triggerPaste(at: model.focusedIndex, modifiers: [])
                }
                return nil
            }

            if registry.matches(event: event, .pastePlain) {
                if model.activeList == .snippets {
                    Task { @MainActor in
                        self.hide()
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        await self.model.pasteFocusedSnippet(plainText: true)
                    }
                } else if !model.selection.isEmpty {
                    Task { @MainActor in
                        await self.model.pasteSelectionInOrder(delimiter: "\n", plainText: true)
                    }
                } else {
                    triggerPaste(at: model.focusedIndex, modifiers: .option)
                }
                return nil
            }

            if model.isQuickLooking || ClipboardSystemQuickLookCoordinator.shared.isVisible {
                if event.keyCode == 124 {
                    // Boundary no-op: at the rightmost card focusForward is
                    // a no-op on focusedIndex, but we'd still re-fire the
                    // preview show() and SwiftUI would briefly flash. Skip
                    // the re-show when focus didn't actually move.
                    let before = model.focusedIndex
                    model.focusForward()
                    if model.focusedIndex != before, ClipboardSystemQuickLookCoordinator.shared.isVisible {
                        showSystemQuickLookForFocused()
                    }
                    return nil
                }
                if event.keyCode == 123 {
                    let before = model.focusedIndex
                    model.focusBackward()
                    if model.focusedIndex != before, ClipboardSystemQuickLookCoordinator.shared.isVisible {
                        showSystemQuickLookForFocused()
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
                if model.activeList == .snippets {
                    model.copyFocusedSnippet()
                    CopyHUD.show("Copied")
                    hide()
                } else {
                    Task { @MainActor in
                        await self.model.copyEffectiveTargets(plainText: false)
                    }
                }
                return nil
            }

            // ⌘A → select every visible card (capped at 50 by selectAllVisible).
            if keyMods == .command, event.charactersIgnoringModifiers == "a" {
                model.selectAllVisible()
                return nil
            }

            if !isTextEditingFirstResponder(in: window),
               let updatedQuery = DockTypingSearch.updatedQuery(
                current: model.search,
                keyCode: event.keyCode,
                characters: event.characters,
                modifiers: event.modifierFlags
               )
            {
                model.search = updatedQuery
                model.requestSearchFocus()
                return nil
            }

            if keyMods.isEmpty {
                switch event.keyCode {
                case 0x7B:
                    let before = model.focusedIndex
                    model.focusBackward()
                    if model.focusedIndex != before, ClipboardSystemQuickLookCoordinator.shared.isVisible {
                        showSystemQuickLookForFocused()
                    }
                    return nil
                case 0x7C:
                    let before = model.focusedIndex
                    model.focusForward()
                    if model.focusedIndex != before, ClipboardSystemQuickLookCoordinator.shared.isVisible {
                        showSystemQuickLookForFocused()
                    }
                    return nil
                default:
                    break
                }
            }

            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalKeyDown(event)
            }
        }

        let fallbackBindings = DockGlobalKeyFallbackBindings(
            quickLook: registry.bindings(for: .quickLook),
            dismiss: registry.bindings(for: .dismiss)
        )
        let eventTap = DockGlobalKeyEventTap(bindings: fallbackBindings) { [weak self] action in
            self?.handleGlobalKeyFallbackAction(action)
        }
        if eventTap.start() {
            globalKeyEventTap = eventTap
        }
    }

    private func startDragMonitor() {
        stopDragMonitor()
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            if event.type == .leftMouseUp {
                self?.deactivateDockDragSurface()
                return event
            }

            guard let self,
                  let window = self.window,
                  window.isVisible,
                  let eventWindow = event.window,
                  eventWindow == window
            else {
                return event
            }

            self.activateDockDragSurfaceForCurrentDrag()
            self.ignoreOutsideClicksUntil = Date().addingTimeInterval(0.8)
            return event
        }
    }

    private func stopDragMonitor() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        deactivateDockDragSurface()
    }

    private func activateDockDragSurfaceForCurrentDrag() {
        model.isDockDragSurfaceActive = true
        dragSurfaceClearTask?.cancel()
        dragSurfaceClearTask = Task { @MainActor [weak model] in
            try? await Task.sleep(for: .seconds(3))
            model?.isDockDragSurfaceActive = false
        }
    }

    private func deactivateDockDragSurface() {
        dragSurfaceClearTask?.cancel()
        dragSurfaceClearTask = nil
        model.isDockDragSurfaceActive = false
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        globalKeyEventTap?.stop()
        globalKeyEventTap = nil
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard let window, window.isVisible else { return }

        let modifierMask = event.modifierFlags.rawValue
            & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        let fallbackBindings = DockGlobalKeyFallbackBindings(
            quickLook: registry.bindings(for: .quickLook),
            dismiss: registry.bindings(for: .dismiss)
        )
        guard let action = DockGlobalKeyFallbackPolicy.action(
            keyCode: event.keyCode,
            modifierMask: modifierMask,
            bindings: fallbackBindings
        ) else { return }

        handleGlobalKeyFallbackAction(action)
    }

    private func handleGlobalKeyFallbackAction(_ action: DockGlobalKeyFallbackAction) {
        guard let window, window.isVisible else { return }

        switch action {
        case .quickLook:
            toggleSystemQuickLookForFocused()
        case .dismiss:
            if model.isQuickLooking {
                model.isQuickLooking = false
            } else if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                ClipboardSystemQuickLookCoordinator.shared.dismiss()
            } else {
                hide()
            }
        case .focusForward:
            let before = model.focusedIndex
            model.focusForward()
            if model.focusedIndex != before, ClipboardSystemQuickLookCoordinator.shared.isVisible {
                showSystemQuickLookForFocused()
            }
        case .focusBackward:
            let before = model.focusedIndex
            model.focusBackward()
            if model.focusedIndex != before, ClipboardSystemQuickLookCoordinator.shared.isVisible {
                showSystemQuickLookForFocused()
            }
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

    /// Open the native macOS Quick Look panel for the focused card.
    @discardableResult
    func showSystemQuickLookForFocused() -> Bool {
        guard model.items.indices.contains(model.focusedIndex),
              let clip = model.clip
        else { return false }
        let item = model.items[model.focusedIndex]
        guard let rid = Core.RecordID(rawValue: item.id),
              let body = try? clip.body(for: rid)
        else { return false }
        ClipboardSystemQuickLookCoordinator.shared.show(
            record: body,
            title: previewTitle(for: item),
            blobs: model.blobs
        )
        return true
    }

    private func toggleSystemQuickLookForFocused() {
        if ClipboardSystemQuickLookCoordinator.shared.isVisible {
            ClipboardSystemQuickLookCoordinator.shared.dismiss()
        } else {
            showSystemQuickLookForFocused()
        }
    }

    private func previewTitle(for item: DockItem) -> String {
        let title = item.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Clipboard Preview" : title
    }
}
