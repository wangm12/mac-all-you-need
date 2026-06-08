import ApplicationServices
import Foundation
import Platform

/// Unified Dock hub runtime: hover previews, switcher, Cmd+Tab, lock, and indicator.
@MainActor
final class DockHubRuntime {
    private let dockWorker: DockPreviewWorker
    private let panelController = DockPreviewPanelController()
    private let hoverCoordinator: DockPreviewCoordinator
    private let manipulationObservers = DockWindowManipulationObservers()
    private let keybindController: DockKeybindController
    private let cmdTabController: DockCmdTabController
    private let dockLockController = DockLockingController()
    private let indicatorController = DockActiveIndicatorController()
    private lazy var gestureController: DockGestureController = {
        DockGestureController(
            hoverObserver: hoverCoordinator.dockHoverObserver,
            panelController: panelController
        )
    }()

    private lazy var trustMonitor: WindowControlAccessibilityTrustMonitor = {
        WindowControlAccessibilityTrustMonitor(
            onTrustChanged: { [weak self] trusted in
                self?.handleAccessibilityTrustChanged(trusted)
            },
            shouldPoll: { [weak self] in
                guard let self else { return false }
                return self.featureEnabled && !self.suspendedForHotkeyRecording
            }
        )
    }()

    private var hubSettings = DockHubSettings.default
    private var isActive = false
    private var featureEnabled = false
    private var suspendedForHotkeyRecording = false

    init(dockWorker: DockPreviewWorker) {
        self.dockWorker = dockWorker
        let engine = SystemAXObserverEngine()
        let axCoordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 5)
        hoverCoordinator = DockPreviewCoordinator(
            panelController: panelController,
            coordinator: axCoordinator,
            dockWorker: dockWorker
        )
        keybindController = DockKeybindController(
            panelController: panelController,
            windowCache: hoverCoordinator.cache,
            capturePipeline: hoverCoordinator.capturePipeline,
            hydrateEntries: { [weak hoverCoordinator] entries in
                guard let hoverCoordinator else { return entries }
                return await hoverCoordinator.hydrateForDisplayAsync(entries)
            },
            onSwitcherSessionPIDs: { [weak hoverCoordinator] pids in
                hoverCoordinator?.noteSwitcherSession(pids: pids)
            },
            onDisplaySessionEnd: { [weak hoverCoordinator] in
                hoverCoordinator?.clearSwitcherSession()
                hoverCoordinator?.evictVisibleThumbnails()
            }
        )
        cmdTabController = DockCmdTabController(panelController: panelController)
        hoverCoordinator.onAppHoverPID = { [weak self] pid in
            guard let self else { return }
            if let pid {
                self.gestureController.noteHoverBegan(pid: pid)
            } else {
                self.gestureController.noteHoverEnded()
            }
        }
        hoverCoordinator.dockHoverObserver.onSystemWakeRecovery = { [weak self] in
            self?.runDockHealthRecovery()
        }
        hoverCoordinator.dockHoverObserver.onPeriodicHealthCheck = { [weak self] in
            self?.gestureController.recoverEventTapIfNeeded()
        }
    }

    private func runDockHealthRecovery() {
        guard isActive else { return }
        gestureController.recoverEventTapIfNeeded()
        hoverCoordinator.refreshCachesAfterWake()
    }

    func applyEnabled(_ enabled: Bool) {
        featureEnabled = enabled
        reconcileRunningState()
    }

    func reloadSettings() {
        hubSettings = DockHubSettingsStore.load()
        hoverCoordinator.reloadSettings(hub: hubSettings)
        keybindController.apply(settings: hubSettings)
        cmdTabController.apply(settings: hubSettings)
        dockLockController.apply(settings: hubSettings)
        indicatorController.apply(settings: hubSettings)
        gestureController.apply(settings: hubSettings)
    }

    func suspendForHotkeyRecording() {
        suspendedForHotkeyRecording = true
        reconcileRunningState()
    }

    func resumeAfterHotkeyRecording() {
        suspendedForHotkeyRecording = false
        reconcileRunningState()
    }

    func refreshPermissions() {
        hoverCoordinator.refreshPermissions()
    }

    private func handleAccessibilityTrustChanged(_ trusted: Bool) {
        if trusted {
            reconcileRunningState()
        } else {
            stopAll()
            isActive = false
        }
    }

    private func reconcileRunningState() {
        trustMonitor.start()
        reloadSettings()
        let shouldRun = featureEnabled && !suspendedForHotkeyRecording && AXIsProcessTrusted()
        guard shouldRun != isActive else { return }
        isActive = shouldRun
        if shouldRun {
            startAll()
        } else {
            stopAll()
        }
    }

    private func startAll() {
        if hubSettings.master.enableDockPreviews {
            hoverCoordinator.start()
            DockPreviewMagnificationNotice.presentIfNeeded()
            manipulationObservers.onApplicationActivated = { [weak self] in
                self?.hoverCoordinator.handleApplicationActivated()
            }
            manipulationObservers.start(cache: hoverCoordinator.cache)
        } else if hubSettings.master.enableWindowSwitcher {
            hoverCoordinator.startWindowCacheOnly()
        }
        if hubSettings.master.enableWindowSwitcher {
            keybindController.apply(settings: hubSettings)
        }
        if hubSettings.master.enableCmdTabEnhancements {
            cmdTabController.apply(settings: hubSettings)
        }
        if hubSettings.master.enableDockLocking {
            dockLockController.apply(settings: hubSettings)
        }
        if hubSettings.master.enableActiveAppIndicator {
            indicatorController.apply(settings: hubSettings)
        }
        if hubSettings.master.enableDockPreviews || hubSettings.gestures.enableDockScrollGesture {
            gestureController.apply(settings: hubSettings)
        }
    }

    private func stopAll() {
        hoverCoordinator.stop()
        manipulationObservers.stop()
        keybindController.stop()
        cmdTabController.stop()
        dockLockController.stop()
        indicatorController.stop()
        gestureController.stop()
    }
}
