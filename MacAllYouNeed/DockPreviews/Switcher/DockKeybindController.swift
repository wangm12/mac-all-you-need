import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Platform

/// Global window switcher (Option+Tab by default) via CGEvent tap — matches DockDoor KeybindHelper timing.
@MainActor
final class DockKeybindController {
    private weak var panelController: DockPreviewPanelController?
    private let windowCache: DockPreviewWindowCache
    private let capturePipeline: DockPreviewWindowCapturePipeline
    private let hydrateEntries: ([DockPreviewWindowEntry]) async -> [DockPreviewWindowEntry]
    private let onSwitcherSessionPIDs: ([pid_t]) -> Void
    private let onDisplaySessionEnd: () -> Void
    private var hubSettings: DockHubSettings = .default

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Read from the event-tap thread — updated only on MainActor in apply()/session methods.
    private nonisolated(unsafe) var tapKeyCode: UInt16 = UInt16(kVK_Tab)
    private nonisolated(unsafe) var tapModifiers: UInt32 = UInt32(optionKey)
    private nonisolated(unsafe) var tapSessionActive = false

    private var entries: [DockPreviewWindowEntry] = []
    private var selectedIndex = 0
    private var sessionActive = false
    private var pendingSession = false
    private var refreshTask: Task<Void, Never>?

    private var switcherModifierHeld = false
    private var hasProcessedModifierRelease = false
    private var shouldSelectImmediately = false
    private var preventHideOnRelease = false
    private var pendingTabCycles = 0

    init(
        panelController: DockPreviewPanelController,
        windowCache: DockPreviewWindowCache,
        capturePipeline: DockPreviewWindowCapturePipeline,
        hydrateEntries: @escaping ([DockPreviewWindowEntry]) async -> [DockPreviewWindowEntry] = { $0 },
        onSwitcherSessionPIDs: @escaping ([pid_t]) -> Void = { _ in },
        onDisplaySessionEnd: @escaping () -> Void = {}
    ) {
        self.panelController = panelController
        self.windowCache = windowCache
        self.capturePipeline = capturePipeline
        self.hydrateEntries = hydrateEntries
        self.onSwitcherSessionPIDs = onSwitcherSessionPIDs
        self.onDisplaySessionEnd = onDisplaySessionEnd
    }

    func apply(settings: DockHubSettings) {
        hubSettings = settings
        capturePipeline.reloadSettings(hub: settings)
        tapKeyCode = settings.switcher.shortcutKeyCode
        tapModifiers = settings.switcher.shortcutModifiers
        stopEventTap()
        stopSession()
        guard settings.master.enableWindowSwitcher, AXIsProcessTrusted() else { return }
        installEventTap()
    }

    func stop() {
        stopEventTap()
        stopSession()
    }

    // MARK: - Event tap

    private func installEventTap() {
        var mask: CGEventMask = 0
        mask |= 1 << CGEventType.keyDown.rawValue
        mask |= 1 << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<DockKeybindController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleCGEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private nonisolated func handleCGEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .flagsChanged:
            let held = Self.modifiersMatch(event.flags, saved: tapModifiers)
            DispatchQueue.main.async { [weak self] in
                self?.handleModifierFlagsChanged(held: held)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            if tapSessionActive {
                if isAutoRepeat, keyCode == tapKeyCode {
                    return nil
                }
                DispatchQueue.main.async { [weak self] in
                    self?.handleSessionKeyDown(keyCode: keyCode, flags: event.flags)
                }
                return nil
            }

            guard keyCode == tapKeyCode, Self.modifiersMatch(event.flags, saved: tapModifiers) else {
                return Unmanaged.passUnretained(event)
            }

            if isAutoRepeat {
                return nil
            }

            let shift = event.flags.contains(.maskShift)
            DispatchQueue.main.async { [weak self] in
                self?.handleSwitcherTab(shift: shift)
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private nonisolated static func modifiersMatch(_ flags: CGEventFlags, saved: UInt32) -> Bool {
        let wantsAlt = (saved & UInt32(optionKey)) != 0
        let wantsCtrl = (saved & UInt32(controlKey)) != 0
        let wantsCmd = (saved & UInt32(cmdKey)) != 0
        let wantsShift = (saved & UInt32(shiftKey)) != 0
        return wantsAlt == flags.contains(.maskAlternate)
            && wantsCtrl == flags.contains(.maskControl)
            && wantsCmd == flags.contains(.maskCommand)
            && wantsShift == flags.contains(.maskShift)
    }

    // MARK: - Session lifecycle

    private func handleSwitcherTab(shift: Bool) {
        if DockSwitcherUtilities.shouldIgnoreKeybind(blacklist: hubSettings.switcher.fullscreenAppBlacklist) {
            return
        }
        if hubSettings.switcher.instantSwitcher {
            Task { await cycleInstant() }
            return
        }

        if sessionActive {
            cycleSelection(delta: shift ? -1 : 1)
            return
        }

        if pendingSession {
            pendingTabCycles += shift ? -1 : 1
            return
        }

        beginSession()
    }

    private func handleSessionKeyDown(keyCode: UInt16, flags: CGEventFlags) {
        guard sessionActive else { return }

        if keyCode == tapKeyCode {
            cycleSelection(delta: flags.contains(.maskShift) ? -1 : 1)
            return
        }

        if handleSearchKeyDown(keyCode: keyCode) { return }
        if handleVimKeyDown(keyCode: keyCode) { return }
        if handleArrowKeyDown(keyCode: keyCode) { return }
    }

    private func handleModifierFlagsChanged(held: Bool) {
        let wasHeld = switcherModifierHeld
        switcherModifierHeld = held

        if !wasHeld, held {
            hasProcessedModifierRelease = false
        }

        guard wasHeld, !held, !hasProcessedModifierRelease else { return }
        guard !hubSettings.switcher.preventSwitcherHide else { return }
        guard !preventHideOnRelease, panelController?.isSearchWindowFocused != true else { return }

        hasProcessedModifierRelease = true

        if sessionActive {
            activateSelection()
            stopSession()
        } else if pendingSession {
            shouldSelectImmediately = true
            refreshTask?.cancel()
            refreshTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let collected = await DockSwitcherWindowCollector.refreshParallel(
                    cache: self.windowCache,
                    pipeline: self.capturePipeline,
                    hub: self.hubSettings
                )
                guard !Task.isCancelled else { return }
                self.finishSessionBootstrap(with: collected)
            }
        }
    }

    private func beginSession() {
        pendingSession = true
        shouldSelectImmediately = false
        pendingTabCycles = 0
        hasProcessedModifierRelease = false

        let cached = DockSwitcherWindowCollector.collectCached(cache: windowCache, hub: hubSettings)
        if !cached.isEmpty, switcherModifierHeld {
            openSwitcherSession(with: cached)
        }

        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let fresh = await DockSwitcherWindowCollector.refreshParallel(
                cache: self.windowCache,
                pipeline: self.capturePipeline,
                hub: self.hubSettings
            )
            guard !Task.isCancelled else { return }
            self.finishSessionBootstrap(with: fresh)
        }
    }

    private func finishSessionBootstrap(with collected: [DockPreviewWindowEntry]) {
        pendingSession = false
        Task { @MainActor in
            await self.finishSessionBootstrapAsync(with: collected)
        }
    }

    private func finishSessionBootstrapAsync(with collected: [DockPreviewWindowEntry]) async {
        if shouldSelectImmediately {
            shouldSelectImmediately = false
            pendingTabCycles = 0
            let index = resolvedSelectionIndex(in: collected)
            if collected.indices.contains(index) {
                raiseWindow(collected[index])
            } else if let first = collected.first {
                raiseWindow(first)
            }
            return
        }

        guard switcherModifierHeld, !collected.isEmpty else { return }

        let display = await hydrateEntries(collected)
        if sessionActive {
            entries = display
            onSwitcherSessionPIDs(display.map(\.pid).filter { $0 != 0 })
            panelController?.mergeSwitcherEntries(display)
            applyPendingTabCycles()
        } else {
            openSwitcherSession(with: display)
        }
    }

    private func openSwitcherSession(with collected: [DockPreviewWindowEntry]) {
        entries = collected
        onSwitcherSessionPIDs(collected.map(\.pid).filter { $0 != 0 })
        let startIndex = hubSettings.switcher.useClassicWindowOrdering && collected.count > 1 ? 1 : 0
        selectedIndex = startIndex
        sessionActive = true
        tapSessionActive = true
        panelController?.state.searchQuery = ""
        panelController?.showSwitcher(entries: collected, selectedIndex: startIndex)
        applyPendingTabCycles()
    }

    private func applyPendingTabCycles() {
        guard pendingTabCycles != 0 else { return }
        let cycles = pendingTabCycles
        pendingTabCycles = 0
        let delta = cycles > 0 ? 1 : -1
        for _ in 0..<abs(cycles) {
            cycleSelection(delta: delta)
        }
    }

    private func resolvedSelectionIndex(in collected: [DockPreviewWindowEntry]) -> Int {
        if hubSettings.switcher.useClassicWindowOrdering, collected.count > 1 {
            return min(1, collected.count - 1)
        }
        return 0
    }

    private func stopSession() {
        sessionActive = false
        tapSessionActive = false
        pendingSession = false
        shouldSelectImmediately = false
        pendingTabCycles = 0
        preventHideOnRelease = false
        refreshTask?.cancel()
        refreshTask = nil
        entries = []
        panelController?.hideSearchWindow()
        panelController?.dismiss(animated: true)
        onDisplaySessionEnd()
    }

    // MARK: - Selection

    private func cycleSelection(delta: Int) {
        guard !entries.isEmpty, let panelController else { return }
        panelController.state.selectNext(delta: delta)
        selectedIndex = panelController.state.selectedIndex
        panelController.updateSwitcherSelection(selectedIndex: selectedIndex)
    }

    private func activateSelection() {
        guard let panelController else { return }
        let windows = panelController.state.windows
        var index = panelController.state.selectedIndex
        if !windows.indices.contains(index) {
            index = resolvedSelectionIndex(in: windows)
        }
        guard windows.indices.contains(index) else { return }
        raiseWindow(windows[index])
    }

    private func raiseWindow(_ entry: DockPreviewWindowEntry) {
        DockSwitcherUtilities.warpMouseToWindowCenter(
            entry: entry,
            mode: hubSettings.switcher.mouseFollowsFocus
        )
        Task {
            await DockPreviewRaiseService(enumerator: SystemWindowEnumerator())
                .raise(entry: entry, settings: hubSettings.previews)
        }
    }

    private func cycleInstant() async {
        if DockSwitcherUtilities.shouldIgnoreKeybind(blacklist: hubSettings.switcher.fullscreenAppBlacklist) {
            return
        }
        var collected = DockSwitcherWindowCollector.collectCached(cache: windowCache, hub: hubSettings)
        if collected.isEmpty {
            collected = await DockSwitcherWindowCollector.refreshParallel(
                cache: windowCache,
                pipeline: capturePipeline,
                hub: hubSettings
            )
        }
        let index = resolvedSelectionIndex(in: collected)
        guard collected.indices.contains(index) else { return }
        raiseWindow(collected[index])
    }

    // MARK: - In-session keys

    private func handleSearchKeyDown(keyCode: UInt16) -> Bool {
        guard hubSettings.switcher.enableSearch, let panelController else { return false }

        if keyCode == hubSettings.switcher.searchTriggerKeyCode, !panelController.isSearchWindowFocused {
            panelController.focusSearchWindow()
            preventHideOnRelease = true
            return true
        }

        guard !panelController.isSearchWindowFocused else { return false }

        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) {
            var query = panelController.state.searchQuery
            if !query.isEmpty {
                query.removeLast()
                panelController.state.searchQuery = query
                panelController.updateSearchWindow(text: query)
                panelController.state.clampSelectionToFilteredSearch()
                panelController.mergeSwitcherEntries(entries)
                if query.isEmpty { preventHideOnRelease = false }
            }
            return true
        }

        return false
    }

    private func handleVimKeyDown(keyCode: UInt16) -> Bool {
        guard hubSettings.switcher.enableVimMotions else { return false }
        switch keyCode {
        case UInt16(kVK_ANSI_H): cycleSelection(delta: -1); return true
        case UInt16(kVK_ANSI_L): cycleSelection(delta: 1); return true
        case UInt16(kVK_ANSI_J): cycleSelection(delta: 1); return true
        case UInt16(kVK_ANSI_K): cycleSelection(delta: -1); return true
        default: return false
        }
    }

    private func handleArrowKeyDown(keyCode: UInt16) -> Bool {
        guard !hubSettings.switcher.passArrowsThrough else { return false }
        switch keyCode {
        case UInt16(kVK_DownArrow):
            panelController?.state.selectedIndex = -1
            panelController?.state.shouldScrollToIndex = true
            panelController?.updateSwitcherSelection(selectedIndex: -1)
            return true
        case UInt16(kVK_LeftArrow), UInt16(kVK_UpArrow):
            cycleSelection(delta: -1)
            return true
        case UInt16(kVK_RightArrow):
            cycleSelection(delta: 1)
            return true
        default:
            return false
        }
    }
}
