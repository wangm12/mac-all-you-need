import AppKit
import ApplicationServices
import Core
import Observation
import Platform

@MainActor
protocol WindowControlTapLifecycle: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func stop()
}

@MainActor
protocol WindowControlActionPerforming: AnyObject {
    var isAvailable: Bool { get }
    var currentIdentity: WindowIdentity? { get }
    func perform(_ action: WindowAction, restoreFrame: CGRect?) -> WindowMovementResult?
}

@MainActor
protocol WindowControlRuntimeConfigurableTap: AnyObject {
    func updateRuntime(
        settings: WindowControlSettings,
        featureAvailability: WindowControlFeatureAvailability,
        axTrusted: Bool,
        coordinatorActive: Bool,
        recordingHotkey: Bool
    )
}

@MainActor
protocol WindowControlMovementReportingTap: AnyObject {
    func setMovementHandler(_ handler: @escaping @MainActor (WindowAction, WindowMovementResult, WindowIdentity?) -> Void)
}

extension WindowControlActionPerforming {
    var isAvailable: Bool { true }
}

struct WindowControlFeatureAvailability: Equatable {
    var windowLayoutsEnabled: Bool
    var windowGrabEnabled: Bool

    static let enabled = WindowControlFeatureAvailability(
        windowLayoutsEnabled: true,
        windowGrabEnabled: true
    )

    static let disabled = WindowControlFeatureAvailability(
        windowLayoutsEnabled: false,
        windowGrabEnabled: false
    )
}

@MainActor
@Observable
final class WindowControlCoordinator {
    enum State: Equatable {
        case off
        case needsAccessibility
        case active
        case suspended(SuspensionReason)
        case error(String)
    }

    enum SuspensionReason: Equatable {
        case hotkeyRecording
        case ignoredApp
    }

    private(set) var state: State = .off
    private(set) var settings: WindowControlSettings
    private(set) var featureAvailability: WindowControlFeatureAvailability
    private(set) var lastAction: WindowAction?
    private(set) var lastMovementResult: WindowMovementResult?

    private let tap: any WindowControlTapLifecycle
    private let actionPerformer: any WindowControlActionPerforming
    private let restoreHistory: WindowRestoreHistory
    private let accessibilityTrust: () -> Bool
    private let frontmostBundleID: () -> String?
    private var onHotkeyRegistrationNeedsRefresh: () -> Void

    private var axTrusted: Bool
    private var suspendedForHotkeyRecording = false

    /// Radial window-management menu coordinator. Lazily constructed so it can
    /// reference `self` as both action performer and frame resolver.
    @ObservationIgnored
    lazy var radialMenuCoordinator: RadialMenuCoordinator = .init(
        actionPerformer: self,
        frameResolver: self
    )

    @ObservationIgnored let radialFrameMover = WindowMover()
    @ObservationIgnored let radialMenuViewModel = RadialMenuViewModel()
    @ObservationIgnored let radialPreviewViewModel = RadialPreviewViewModel()
    @ObservationIgnored lazy var radialMenuController = RadialMenuController(viewModel: radialMenuViewModel)
    @ObservationIgnored lazy var radialPreviewController = RadialPreviewController(viewModel: radialPreviewViewModel)

    init(
        settings: WindowControlSettings = WindowControlSettingsStore.load(),
        featureAvailability: WindowControlFeatureAvailability = .enabled,
        tap: (any WindowControlTapLifecycle)? = nil,
        actionPerformer: (any WindowControlActionPerforming)? = nil,
        restoreHistory: WindowRestoreHistory = WindowRestoreHistory(),
        accessibilityTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
        frontmostBundleID: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        onHotkeyRegistrationNeedsRefresh: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.featureAvailability = featureAvailability
        self.tap = tap ?? WindowControlEventTap()
        self.actionPerformer = actionPerformer ?? WindowKeyboardActionPerformer()
        self.restoreHistory = restoreHistory
        self.accessibilityTrust = accessibilityTrust
        self.frontmostBundleID = frontmostBundleID
        self.onHotkeyRegistrationNeedsRefresh = onHotkeyRegistrationNeedsRefresh
        axTrusted = accessibilityTrust()
        (self.tap as? WindowControlMovementReportingTap)?.setMovementHandler { [weak self] action, result, identity in
            self?.recordMovement(action: action, result: result, identity: identity)
        }
        if let eventTap = self.tap as? WindowControlEventTap {
            let snapOverlay = WindowSnapOverlayPanel()
            eventTap.setSnapOverlay(
                show: { snapOverlay.show(frame: $0) },
                hide: { snapOverlay.hide() }
            )
            eventTap.restoreFrameLookup = { [weak self] identity in
                self?.restoreHistory.restoreFrame(for: identity)
            }
            eventTap.radialPhaseHandler = { [weak self] phase in
                self?.handleRadialPhase(phase)
            }
        }
    }

    var windowActionPerformerAvailable: Bool {
        layoutsRuntimeEnabled && axTrusted && !suspendedForHotkeyRecording && actionPerformer.isAvailable
    }

    var windowLayoutsEnabled: Bool {
        featureAvailability.windowLayoutsEnabled
    }

    var windowGrabEnabled: Bool {
        featureAvailability.windowGrabEnabled
    }

    var shouldPollAccessibilityTrust: Bool {
        WindowControlAccessibilityTrustMonitor.shouldPoll(
            runtimeEnabled: anyRuntimeBehaviorEnabled,
            coordinatorState: state
        )
    }

    func start() {
        axTrusted = accessibilityTrust()
        reconcileLifecycle()
    }

    func stop() {
        tap.stop()
        suspendedForHotkeyRecording = false
        state = .off
    }

    func reloadSettings() {
        applySettings(WindowControlSettingsStore.load())
    }

    func setHotkeyRegistrationNeedsRefresh(_ handler: @escaping () -> Void) {
        onHotkeyRegistrationNeedsRefresh = handler
    }

    func applySettings(_ next: WindowControlSettings) {
        let wasAvailable = windowActionPerformerAvailable
        let layoutsRuntimeChanged = layoutsRuntimeEnabled != (featureAvailability.windowLayoutsEnabled && next.enabled)
        let radialChanged = settings.radialMenuEnabled != next.radialMenuEnabled
        settings = next
        if radialChanged {
            // The CGEvent tap mask can only be set at creation, so flipping the
            // radial setting requires recreating the tap; stop it here and let
            // reconcileLifecycle restart it with the updated mask.
            (tap as? WindowControlEventTap)?.updateRuntime(radialMenuEnabled: next.radialMenuEnabled)
        }
        reconcileLifecycle()
        if layoutsRuntimeChanged || wasAvailable != windowActionPerformerAvailable {
            onHotkeyRegistrationNeedsRefresh()
        }
    }

    func applyFeatureAvailability(_ availability: WindowControlFeatureAvailability) {
        let wasAvailable = windowActionPerformerAvailable
        let layoutsChanged = featureAvailability.windowLayoutsEnabled != availability.windowLayoutsEnabled
        featureAvailability = availability
        reconcileLifecycle()
        if layoutsChanged || wasAvailable != windowActionPerformerAvailable {
            onHotkeyRegistrationNeedsRefresh()
        }
    }

    func refreshAccessibilityTrust(_ trusted: Bool? = nil) {
        let wasAvailable = windowActionPerformerAvailable
        axTrusted = trusted ?? accessibilityTrust()
        reconcileLifecycle()
        if wasAvailable != windowActionPerformerAvailable {
            onHotkeyRegistrationNeedsRefresh()
        }
    }

    func suspendForHotkeyRecording() {
        guard !suspendedForHotkeyRecording else { return }
        suspendedForHotkeyRecording = true
        tap.stop()
        state = .suspended(.hotkeyRecording)
    }

    func resumeAfterHotkeyRecording() {
        guard suspendedForHotkeyRecording else { return }
        suspendedForHotkeyRecording = false
        reconcileLifecycle()
    }

    func perform(action: WindowAction) {
        guard layoutsRuntimeEnabled else {
            reconcileLifecycle()
            return
        }
        guard axTrusted else {
            state = .needsAccessibility
            return
        }
        guard !suspendedForHotkeyRecording else {
            state = .suspended(.hotkeyRecording)
            return
        }
        if let bundleID = frontmostBundleID(),
           settings.ignoredBundleIDs.contains(bundleID)
        {
            state = .suspended(.ignoredApp)
            return
        }

        reconcileLifecycle()
        guard windowActionPerformerAvailable else {
            return
        }
        let identity = actionPerformer.currentIdentity
        let restoreFrame = action == .restore ? identity.flatMap { restoreHistory.restoreFrame(for: $0) } : nil
        let result = actionPerformer.perform(action, restoreFrame: restoreFrame)
        if let result {
            recordMovement(action: action, result: result, identity: identity)
        } else {
            lastAction = action
            lastMovementResult = nil
        }
    }

    private func reconcileLifecycle() {
        guard anyRuntimeBehaviorEnabled else {
            updateTapRuntime(coordinatorActive: false)
            tap.stop()
            state = .off
            return
        }
        guard axTrusted else {
            updateTapRuntime(coordinatorActive: false)
            tap.stop()
            state = .needsAccessibility
            return
        }
        guard !suspendedForHotkeyRecording else {
            updateTapRuntime(coordinatorActive: false)
            tap.stop()
            state = .suspended(.hotkeyRecording)
            return
        }

        do {
            updateTapRuntime(coordinatorActive: true)
            try tap.start()
            state = .active
        } catch {
            updateTapRuntime(coordinatorActive: false)
            tap.stop()
            state = .error(error.localizedDescription)
        }
    }

    private func updateTapRuntime(coordinatorActive: Bool) {
        (tap as? WindowControlRuntimeConfigurableTap)?.updateRuntime(
            settings: settings,
            featureAvailability: featureAvailability,
            axTrusted: axTrusted,
            coordinatorActive: coordinatorActive,
            recordingHotkey: suspendedForHotkeyRecording
        )
    }

    private var layoutsRuntimeEnabled: Bool {
        featureAvailability.windowLayoutsEnabled && settings.enabled
    }

    private var grabRuntimeEnabled: Bool {
        featureAvailability.windowGrabEnabled && settings.enabled && settings.dragAnywhereEnabled
    }

    private var anyRuntimeBehaviorEnabled: Bool {
        layoutsRuntimeEnabled || grabRuntimeEnabled
    }

    private func recordMovement(
        action: WindowAction,
        result: WindowMovementResult,
        identity: WindowIdentity?
    ) {
        lastAction = action
        lastMovementResult = result
        if action != .restore, let identity, result.status == .moved {
            restoreHistory.store(result.originalFrame, for: identity)
        }
    }
}

@MainActor
private final class WindowControlInactiveTap: WindowControlTapLifecycle {
    private(set) var isRunning = false

    func start() throws {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
