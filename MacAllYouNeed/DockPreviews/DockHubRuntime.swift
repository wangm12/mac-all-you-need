import ApplicationServices
import Foundation
import Platform

/// Unified Dock hub runtime: hover previews, switcher, Cmd+Tab, lock, indicator, gestures.
@MainActor
final class DockHubRuntime {
    private let panelController = DockPreviewPanelController()
    private let hoverCoordinator: DockPreviewCoordinator
    private let manipulationObservers = DockWindowManipulationObservers()
    private let keybindController: DockKeybindController
    private let cmdTabController: DockCmdTabController
    private let dockLockController = DockLockingController()
    private let indicatorController = DockActiveIndicatorController()
    private let dockGestures = DockGesturesRuntime()

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

    init() {
        let engine = SystemAXObserverEngine()
        let axCoordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 5)
        hoverCoordinator = DockPreviewCoordinator(panelController: panelController, coordinator: axCoordinator)
        keybindController = DockKeybindController(panelController: panelController)
        cmdTabController = DockCmdTabController(panelController: panelController)
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
        let gestures = hubSettings.gestures
        dockGestures.applyEnabled(
            featureEnabled && (
                gestures.enableDockScrollOnIcon
                    || gestures.enableTitleBarScroll
                    || gestures.enablePreviewTrackpadGestures
            ),
            settings: DockGesturesSettings(
                enableDockScroll: gestures.enableDockScrollOnIcon,
                enableTitleBarScroll: gestures.enableTitleBarScroll,
                enablePreviewGestures: gestures.enablePreviewTrackpadGestures
            )
        )
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
            manipulationObservers.start(cache: hoverCoordinator.cache)
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
    }

    private func stopAll() {
        hoverCoordinator.stop()
        manipulationObservers.stop()
        keybindController.stop()
        cmdTabController.stop()
        dockLockController.stop()
        indicatorController.stop()
        dockGestures.applyEnabled(false)
    }
}

/// Backward-compatible alias for AppController.
typealias DockPreviewRuntime = DockHubRuntime
