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

    let tap: any WindowControlTapLifecycle
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
    @ObservationIgnored lazy var radialTargetHighlightController = RadialTargetHighlightController()
    @ObservationIgnored var radialEscMonitor: Any?
    /// Cached AX target for the open radial session (refreshed on open / keyboard select only).
    @ObservationIgnored var radialSessionTargetWindow: WindowAccessibilityElement?
    @ObservationIgnored private let activeWindowBorder = ActiveWindowBorderController()
    @ObservationIgnored private let spaceMover = WindowSpaceMover()

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
        if let custom = actionPerformer {
            self.actionPerformer = custom
        } else {
            self.actionPerformer = WindowKeyboardActionPerformer()
        }
        self.restoreHistory = restoreHistory
        self.accessibilityTrust = accessibilityTrust
        self.frontmostBundleID = frontmostBundleID
        self.onHotkeyRegistrationNeedsRefresh = onHotkeyRegistrationNeedsRefresh
        axTrusted = accessibilityTrust()
        if let keyboardPerformer = self.actionPerformer as? WindowKeyboardActionPerformer {
            keyboardPerformer.repeatHalfAcrossDisplays = settings.repeatHalfAcrossDisplays
        }
        (self.tap as? WindowControlMovementReportingTap)?.setMovementHandler { [weak self] action, result, identity in
            self?.handleMovementResult(action: action, result: result, identity: identity)
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
            eventTap.layoutHotkeyHandler = { [weak self] action in
                self?.perform(action: action)
            }
        }
    }

    func syncLayoutHotkeyBindings(_ bindings: [LayoutHotkeyBinding]) {
        guard let eventTap = tap as? WindowControlEventTap else { return }
        let wasRunning = eventTap.isRunning
        eventTap.updateLayoutHotkeyBindings(bindings)
        if wasRunning, !eventTap.isRunning {
            reconcileLifecycle()
        }
    }

    var windowActionPerformerAvailable: Bool {
        layoutsRuntimeEnabled && axTrusted && !suspendedForHotkeyRecording && actionPerformer.isAvailable
    }

    /// Global shortcuts for layout actions register when the feature is enabled and
    /// Accessibility is trusted — independent of the internal `settings.enabled` pause flag.
    var windowLayoutHotkeysRegisterable: Bool {
        featureAvailability.windowLayoutsEnabled && axTrusted && !suspendedForHotkeyRecording
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
        syncLayoutsMasterSwitchWithFeature()
        reconcileLifecycle()
        onHotkeyRegistrationNeedsRefresh()
    }

    func stop() {
        tap.stop()
        suspendedForHotkeyRecording = false
        state = .off
    }

    func reloadSettings() {
        applySettings(WindowControlSettingsStore.load())
    }

    /// Re-reads the display layout after connect/disconnect or arrangement changes.
    func refreshDisplayLayout() {
        endRadialMenuForDisplayChange()
        if let eventTap = tap as? WindowControlEventTap {
            eventTap.updateRuntime(radialMenuEnabled: settings.radialMenuEnabled)
        }
        retryAfterRecoverableErrorIfNeeded()
        reconcileLifecycle()
        onHotkeyRegistrationNeedsRefresh()
    }

    func setHotkeyRegistrationNeedsRefresh(_ handler: @escaping () -> Void) {
        onHotkeyRegistrationNeedsRefresh = handler
    }

    func applySettings(_ next: WindowControlSettings) {
        let wasAvailable = windowActionPerformerAvailable
        let layoutsRuntimeChanged = layoutsRuntimeEnabled != (featureAvailability.windowLayoutsEnabled && next.enabled)
        let radialChanged = settings.radialMenuEnabled != next.radialMenuEnabled
        settings = next
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animationDuration = MAYNMotionBridge.effectiveDuration(.control, reduceMotion: reduceMotion)
        let animationConfig = WindowMoveAnimationConfiguration(
            enabled: next.animateWindowMoves,
            stepCount: 6,
            totalDuration: animationDuration > 0 ? animationDuration : 0.12,
            reduceMotion: reduceMotion
        )
        if let keyboardPerformer = actionPerformer as? WindowKeyboardActionPerformer {
            keyboardPerformer.repeatHalfAcrossDisplays = next.repeatHalfAcrossDisplays
            keyboardPerformer.animateMoves = next.animateWindowMoves
            keyboardPerformer.animationConfiguration = animationConfig
        }
        radialFrameMover.animateMoves = next.animateWindowMoves
        radialFrameMover.animationConfiguration = animationConfig
        if next.disableSequoiaTilingHotkeys {
            WindowControlPrivateAPI.applySequoiaTilingMitigation(disabled: true)
        } else {
            WindowControlPrivateAPI.applySequoiaTilingMitigation(disabled: false)
        }
        activeWindowBorder.apply(settings: next, runtimeEnabled: layoutsRuntimeEnabled)
        if radialChanged {
            // The CGEvent tap mask can only be set at creation, so flipping the
            // radial setting requires recreating the tap; stop it here and let
            // reconcileLifecycle restart it with the updated mask.
            (tap as? WindowControlEventTap)?.updateRuntime(radialMenuEnabled: next.radialMenuEnabled)
        }
        retryAfterRecoverableErrorIfNeeded()
        reconcileLifecycle()
        if layoutsRuntimeChanged || wasAvailable != windowActionPerformerAvailable {
            onHotkeyRegistrationNeedsRefresh()
        }
    }

    func applyFeatureAvailability(_ availability: WindowControlFeatureAvailability) {
        let wasAvailable = windowActionPerformerAvailable
        let layoutsChanged = featureAvailability.windowLayoutsEnabled != availability.windowLayoutsEnabled
        featureAvailability = availability
        syncLayoutsMasterSwitchWithFeature()
        reconcileLifecycle()
        if layoutsChanged || wasAvailable != windowActionPerformerAvailable {
            onHotkeyRegistrationNeedsRefresh()
        }
    }

    func refreshAccessibilityTrust(_ trusted: Bool? = nil) {
        let wasAvailable = windowActionPerformerAvailable
        let wasRegisterable = windowLayoutHotkeysRegisterable
        axTrusted = trusted ?? accessibilityTrust()
        retryAfterRecoverableErrorIfNeeded()
        reconcileLifecycle()
        if wasAvailable != windowActionPerformerAvailable || wasRegisterable != windowLayoutHotkeysRegisterable {
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
           shouldIgnoreFrontmost(bundleID: bundleID)
        {
            state = .suspended(.ignoredApp)
            return
        }

        reconcileLifecycle()
        guard windowActionPerformerAvailable else {
            return
        }

        let identity = actionPerformer.currentIdentity

        switch action {
        case .nextSpace, .previousSpace:
            performSpaceMove(action)
            return
        default:
            break
        }

        let restoreFrame = action == .restore ? identity.flatMap { restoreHistory.restoreFrame(for: $0) } : nil
        let result = actionPerformer.perform(action, restoreFrame: restoreFrame)
        if let result {
            handleMovementResult(action: action, result: result, identity: identity)
            if settings.animateWindowMoves {
                wireAnimatedMoveCompletionIfNeeded(action: action)
            }
        } else {
            lastAction = action
            lastMovementResult = nil
        }
    }

    private func reconcileLifecycle() {
        guard anyRuntimeBehaviorEnabled else {
            updateTapRuntime(coordinatorActive: false)
            tap.stop()
            activeWindowBorder.stop()
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

        activeWindowBorder.apply(settings: settings, runtimeEnabled: layoutsRuntimeEnabled)
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
        featureAvailability.windowGrabEnabled && settings.dragAnywhereEnabled
    }

    private var anyRuntimeBehaviorEnabled: Bool {
        layoutsRuntimeEnabled || grabRuntimeEnabled
    }

    /// Turns on the layouts master switch when the Window Layouts feature is active.
    /// There is no separate UI for `settings.enabled`; leaving it off prevented hotkeys from registering.
    private func performSpaceMove(_ action: WindowAction) {
        if let bundleID = frontmostBundleID(), shouldIgnoreFrontmost(bundleID: bundleID) {
            state = .suspended(.ignoredApp)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value
        else { return }
        let element = axWindow as! AXUIElement
        let result: WindowSpaceMoveResult = switch action {
        case .nextSpace: spaceMover.moveFrontWindowToNextSpace(element: element)
        case .previousSpace: spaceMover.moveFrontWindowToPreviousSpace(element: element)
        default: .unavailable
        }
        lastAction = action
        lastMovementResult = nil
        presentSpaceMoveFeedback(result)
    }

    private func presentSpaceMoveFeedback(_ result: WindowSpaceMoveResult) {
        switch result {
        case .moved:
            return
        case .unavailable:
            CopyHUD.show("Couldn't move window to another Space", symbol: "exclamationmark.triangle.fill")
        case .separateSpacesDisabled:
            CopyHUD.show(
                "Turn on \"Displays have separate Spaces\" in System Settings",
                symbol: "rectangle.split.2x1"
            )
        case .windowNotFound:
            CopyHUD.show("No movable window found for Space move", symbol: "rectangle.slash")
        }
    }

    private func shouldIgnoreFrontmost(bundleID: String) -> Bool {
        if settings.ignoredBundleIDs.contains(bundleID) { return true }
        let title = focusedWindowTitle()
        return WindowRulesEngine(rules: settings.windowRules).shouldIgnore(bundleID: bundleID, title: title)
    }

    private func focusedWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value,
              CFGetTypeID(axWindow) == AXUIElementGetTypeID()
        else { return nil }
        return WindowAccessibilityElement(axWindow as! AXUIElement).windowTitle
    }

    private func wireAnimatedMoveCompletionIfNeeded(action _: WindowAction) {
        guard settings.animateWindowMoves else { return }
        guard let keyboardPerformer = actionPerformer as? WindowKeyboardActionPerformer else { return }
        let generation = keyboardPerformer.lastAnimatedMoveGeneration
        keyboardPerformer.setAnimatedMoveCompletion(for: generation) { [weak self] result in
            guard let self else { return }
            self.lastMovementResult = result
            self.presentMovementFeedback(for: result)
        }
    }

    private func handleMovementResult(
        action: WindowAction,
        result: WindowMovementResult,
        identity: WindowIdentity?
    ) {
        if action != .restore, let identity, result.status == .moved {
            restoreHistory.store(result.originalFrame, for: identity)
        }
        lastAction = action
        lastMovementResult = result
        guard !isAnimatedInterimResult(result) else { return }
        presentMovementFeedback(for: result)
    }

    private func isAnimatedInterimResult(_ result: WindowMovementResult) -> Bool {
        settings.animateWindowMoves
            && result.proposedFrame != nil
            && result.resultingFrame == result.originalFrame
    }

    private func presentMovementFeedback(for result: WindowMovementResult) {
        if result.status == .moved, settings.snapHapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
        WindowControlMovementFeedback.present(status: result.status, axTrusted: axTrusted)
    }

    private func recordMovement(
        action: WindowAction,
        result: WindowMovementResult,
        identity: WindowIdentity?
    ) {
        handleMovementResult(action: action, result: result, identity: identity)
    }

    func retryAfterRecoverableErrorIfNeeded() {
        guard case .error = state else { return }
        guard anyRuntimeBehaviorEnabled, axTrusted, !suspendedForHotkeyRecording else { return }
        reconcileLifecycle()
    }

    private func syncLayoutsMasterSwitchWithFeature() {
        guard featureAvailability.windowLayoutsEnabled, !settings.enabled else { return }
        var next = settings
        next.enabled = true
        settings = next
        WindowControlSettingsStore.save(next)
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
