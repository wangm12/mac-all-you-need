import AppKit
import Foundation

/// Manages NSEvent pointer/click monitors for DockPreviewCoordinator.
///
/// Owns:
/// - Global + local click monitors (right/other/left mouse down).
/// - Global + local move monitors, installed only while the panel is visible
///   or a pending show is queued (`syncPointerMoveMonitoring`).
/// - Pointer-event coalescing (one evaluation per display-frame).
/// - Context-menu dismissal on secondary click near the dock.
@MainActor
final class DockPreviewPointerMonitor {

    // MARK: - State injected by coordinator

    /// Returns whether the coordinator is running (used to gate event handling).
    var isRunning: () -> Bool = { false }

    /// Returns whether a pending show work item is queued.
    var hasPendingShow: () -> Bool = { false }

    /// Returns whether the preview panel is currently visible.
    var isPanelVisible: () -> Bool = { false }

    /// Returns whether the panel's `resetFadeState` should be triggered on move.
    var shouldResetFadeOnMove: () -> Bool = { false }

    /// Returns whether the pointer is within a region that should keep the preview open.
    var shouldKeepPreviewOpen: () -> Bool = { false }

    /// Returns whether settings prevent preview re-entry during fade-out.
    var preventPreviewReentryDuringFadeOut: () -> Bool = { false }

    // MARK: - Callbacks into coordinator

    var onEvaluatePendingShowCancellation: (() -> Void)?
    var onPollDockSelectionIfNeeded: (() -> Void)?
    var onResetPanelFadeState: (() -> Void)?
    var onContextMenuDismiss: (() -> Void)?

    // MARK: - Private state

    private var clickMonitors: [Any] = []
    private var moveMonitors: [Any] = []
    private var coalescedPointerWorkItem: DispatchWorkItem?
    private var lastDockSelectionPollTime: CFAbsoluteTime = 0

    // MARK: - Install / Remove

    func installClickMonitors() {
        removeAll()
        let clickMask: NSEvent.EventTypeMask = [.rightMouseDown, .otherMouseDown, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] event in
            Task { @MainActor in self?.handlePointerEvent(event) }
        } {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clickMask) { [weak self] event in
            Task { @MainActor in self?.handlePointerEvent(event) }
            return event
        } {
            clickMonitors.append(local)
        }
    }

    func syncMoveMonitoring() {
        let needsMove = isPanelVisible() || hasPendingShow()
        if needsMove, moveMonitors.isEmpty {
            let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] event in
                Task { @MainActor in self?.handlePointerEvent(event) }
            } {
                moveMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
                Task { @MainActor in self?.handlePointerEvent(event) }
                return event
            } {
                moveMonitors.append(local)
            }
        } else if !needsMove, !moveMonitors.isEmpty {
            coalescedPointerWorkItem?.cancel()
            coalescedPointerWorkItem = nil
            for monitor in moveMonitors {
                NSEvent.removeMonitor(monitor)
            }
            moveMonitors = []
        }
    }

    func removeAll() {
        coalescedPointerWorkItem?.cancel()
        coalescedPointerWorkItem = nil
        for monitor in clickMonitors + moveMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors = []
        moveMonitors = []
    }

    // MARK: - Event handling

    private func handlePointerEvent(_ event: NSEvent) {
        guard isRunning() else { return }
        switch event.type {
        case .rightMouseDown, .otherMouseDown:
            handleContextMenuMouseDown(event)
        case .leftMouseDown:
            if isSecondaryClickEvent(event) {
                handleContextMenuMouseDown(event)
            }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            scheduleCoalescedPointerEvaluation()
        default:
            break
        }
    }

    private func scheduleCoalescedPointerEvaluation() {
        coalescedPointerWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.coalescedPointerWorkItem = nil
            self.onEvaluatePendingShowCancellation?()
            if self.isPanelVisible() {
                let now = CFAbsoluteTimeGetCurrent()
                if now - self.lastDockSelectionPollTime >= 0.15 {
                    self.lastDockSelectionPollTime = now
                    self.onPollDockSelectionIfNeeded?()
                }
                if !self.preventPreviewReentryDuringFadeOut(),
                   self.shouldKeepPreviewOpen() {
                    self.onResetPanelFadeState?()
                }
            }
        }
        coalescedPointerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
    }

    private func handleContextMenuMouseDown(_ event: NSEvent) {
        guard isRunning() else { return }
        guard isSecondaryClickEvent(event) else { return }

        let nearDock = DockPreviewDockPosition.isMouseInDockRegion(padding: 48)
        let previewActive = isPanelVisible() || hasPendingShow()
        guard nearDock || previewActive else { return }

        onContextMenuDismiss?()
    }

    private func isSecondaryClickEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown, .otherMouseDown:
            return true
        case .leftMouseDown:
            return event.modifierFlags.contains(.control)
        default:
            return false
        }
    }
}
