import AppKit
import ApplicationServices
import Core
import Platform

final class WindowControlEventTap: WindowControlTapLifecycle, WindowControlRuntimeConfigurableTap, WindowControlMovementReportingTap {
    private struct Runtime {
        var settings = WindowControlSettings.default
        var featureAvailability = WindowControlFeatureAvailability.enabled
        var axTrusted = false
        var coordinatorActive = false
        var recordingHotkey = false

        var layoutsRuntimeEnabled: Bool {
            featureAvailability.windowLayoutsEnabled && settings.enabled
        }

        var grabRuntimeEnabled: Bool {
            featureAvailability.windowGrabEnabled && settings.enabled && settings.dragAnywhereEnabled
        }

        var anyRuntimeBehaviorEnabled: Bool {
            layoutsRuntimeEnabled || grabRuntimeEnabled
        }
    }

    private enum GestureMode {
        case none
        case dragAnywhere
        case nativeTitleBarSnap
    }

    private var tapController: CGEventTapController?
    private var runtime = Runtime()
    private var activeTarget: ResolvedWindowTarget?
    private var activeSnapAction: WindowAction?
    private var gestureMode: GestureMode = .none
    private var snapIntent = WindowSnapIntentTracker()
    private var snapOverlayVisible = false
    private var initialTargetFrame: CGRect?
    var restoreFrameLookup: ((WindowIdentity) -> CGRect?)? = nil
    private let stateMachine = WindowEventTapStateMachine()
    private let resolver: WindowTargetResolver
    private let mover: WindowMover
    private let dragStrategy: NativeTitleBarDragStrategy
    private var movementHandler: (@MainActor (WindowAction, WindowMovementResult, WindowIdentity?) -> Void)?
    private var showSnapOverlay: @MainActor (CGRect) -> Void = { _ in }
    private var hideSnapOverlay: @MainActor () -> Void = {}
    private static let syntheticEventMarker: Int64 = 0x4D41_594E_5744

    // MARK: Radial menu

    /// Whether the current tap was installed with radial trigger events in its
    /// mask. CGEvent tap masks cannot be mutated while running, so flipping
    /// `radialMenuEnabled` requires stopping and recreating the tap.
    var radialKeysInstalled = false

    /// Installed by the coordinator to receive radial trigger phases. Locations
    /// are in CG display coordinates (top-left origin, +Y down).
    var radialPhaseHandler: (@MainActor (RadialPhase) -> Void)?

    /// The modifier combo that, when held alone, arms the radial menu.
    /// Read from settings so the user can configure it.
    var radialTriggerModifier: WindowGestureModifier {
        runtime.settings.radialTriggerModifier
    }

    var radialTriggerTapCount: Int {
        runtime.settings.radialTriggerTapCount
    }

    var radialActive = false

    /// Edge-tracking for double-tap radial triggers.
    var radialTriggerWasHeld = false
    var radialTapLastRelease: (key: ModifierTapShortcut.Key, time: TimeInterval)?

    init(
        resolver: WindowTargetResolver = WindowTargetResolver(),
        mover: WindowMover = WindowMover(),
        dragStrategy: NativeTitleBarDragStrategy = NativeTitleBarDragStrategy()
    ) {
        self.resolver = resolver
        self.mover = mover
        self.dragStrategy = dragStrategy
    }

    var isRunning: Bool {
        tapController != nil
    }

    func updateRuntime(
        settings: WindowControlSettings,
        featureAvailability: WindowControlFeatureAvailability,
        axTrusted: Bool,
        coordinatorActive: Bool,
        recordingHotkey: Bool
    ) {
        runtime = Runtime(
            settings: settings,
            featureAvailability: featureAvailability,
            axTrusted: axTrusted,
            coordinatorActive: coordinatorActive,
            recordingHotkey: recordingHotkey
        )
        stateMachine.updateAccessibilityTrust(axTrusted, enabled: runtime.anyRuntimeBehaviorEnabled)
    }

    func setMovementHandler(_ handler: @escaping @MainActor (WindowAction, WindowMovementResult, WindowIdentity?) -> Void) {
        movementHandler = handler
    }

    func setSnapOverlay(
        show: @escaping @MainActor (CGRect) -> Void,
        hide: @escaping @MainActor () -> Void
    ) {
        showSnapOverlay = show
        hideSnapOverlay = hide
    }

    func start() throws {
        guard tapController == nil else { return }
        stateMachine.start(enabled: runtime.anyRuntimeBehaviorEnabled, axTrusted: runtime.axTrusted)

        let includeRadialKeys = runtime.settings.radialMenuEnabled
        let mask = eventMask(includeRadialKeys: includeRadialKeys)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let controller = CGEventTapController(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            runLoop: .main,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<WindowControlEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: userInfo
        )
        do {
            try controller.install()
        } catch {
            throw WindowControlEventTapError.installFailed
        }
        controller.enable()
        tapController = controller
        radialKeysInstalled = includeRadialKeys
    }

    func stop() {
        cancelGesture()
        stateMachine.stop()
        tapController?.uninstall()
        tapController = nil
        radialActive = false
        radialKeysInstalled = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stateMachine.handleTapDisabled(type == .tapDisabledByTimeout ? .timeout : .userInput)
            if case .recovering = stateMachine.state, let controller = tapController {
                stateMachine.retryNow(enabled: runtime.anyRuntimeBehaviorEnabled, axTrusted: runtime.axTrusted)
                if stateMachine.isTapActive {
                    controller.reenableAfterTimeout()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        if runtime.settings.radialMenuEnabled, runtime.layoutsRuntimeEnabled,
           runtime.axTrusted, runtime.coordinatorActive, !runtime.recordingHotkey,
           type == .flagsChanged || (radialActive && type == .mouseMoved) {
            if handleRadialEvent(type: type, flags: event.flags, location: event.location) {
                return nil
            }
        }

        // When the radial menu is open, a left click commits the current selection.
        if radialActive, type == .leftMouseDown {
            radialActive = false
            if let radialPhaseHandler {
                Task { @MainActor in radialPhaseHandler(.commit) }
            }
            return nil // consume the click
        }

        switch type {
        case .leftMouseDown:
            return handleMouseDown(event, allowsNativeTitleBarTracking: true)
        case .rightMouseDown:
            return handleMouseDown(event, allowsNativeTitleBarTracking: false)
        case .leftMouseDragged, .rightMouseDragged:
            return handleMouseDragged(event)
        case .leftMouseUp, .rightMouseUp:
            return handleMouseUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseDown(_ event: CGEvent, allowsNativeTitleBarTracking: Bool) -> Unmanaged<CGEvent>? {
        let location = event.location
        let isDoubleClick = event.getIntegerValueField(.mouseEventClickState) >= 2
        let dragModifierHeld = runtime.grabRuntimeEnabled
            && modifier(runtime.settings.dragModifier, isHeldIn: event.flags)
        let doubleClickModifierHeld = runtime.layoutsRuntimeEnabled
            && runtime.settings.doubleClickEnabled
            && isDoubleClick
            && modifier(runtime.settings.doubleClickModifier, isHeldIn: event.flags)
        let modifierHeld = dragModifierHeld || doubleClickModifierHeld

        guard runtime.anyRuntimeBehaviorEnabled,
              runtime.axTrusted,
              runtime.coordinatorActive,
              !runtime.recordingHotkey,
              stateMachine.isTapActive,
              !isFrontAppIgnored()
        else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }

        guard let target = resolver.resolveTopmostWindow(at: location) else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }

        guard modifierHeld else {
            if allowsNativeTitleBarTracking, shouldTrackNativeTitleBarSnap(from: location, target: target, flags: event.flags) {
                activeTarget = target
                initialTargetFrame = target.element.frame
                gestureMode = .nativeTitleBarSnap
                beginSnapIntent(at: location)
            } else {
                cancelGesture()
            }
            return Unmanaged.passUnretained(event)
        }

        let context = WindowEventTapMouseDownContext(
            enabled: runtime.anyRuntimeBehaviorEnabled,
            axTrusted: runtime.axTrusted,
            coordinatorActive: runtime.coordinatorActive,
            recordingHotkey: runtime.recordingHotkey,
            modifierHeld: modifierHeld,
            targetIsNormalNonMAYNWindow: true,
            frontAppIgnored: false
        )

        guard stateMachine.handleMouseDown(context) == .suppress else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }

        activeTarget = target
        initialTargetFrame = target.element.frame

        if doubleClickModifierHeld {
            performDoubleClickToggle(target)
            cancelGesture()
            return nil
        }

        guard dragModifierHeld else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }

        activateTargetForNativeDrag(target)
        beginSnapIntent(at: location)
        let decision = dragStrategy.handle(
            .mouseDown(at: location, axTrusted: runtime.axTrusted),
            target: target.element
        )
        guard dragStrategy.isActive else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }
        gestureMode = .dragAnywhere
        return eventResponse(for: decision, originalEvent: event)
    }

    private func handleMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch gestureMode {
        case .dragAnywhere:
            guard activeTarget != nil, dragStrategy.isActive else {
                return Unmanaged.passUnretained(event)
            }
            clampMissionControlDragLocation(event)
            let decision = dragStrategy.handle(
                .mouseDragged(to: event.location, axTrusted: runtime.axTrusted)
            )
            if dragStrategy.didDrag {
                updateSnapOverlay(at: event.location, flags: event.flags)
            } else {
                hideSnapOverlayIfNeeded()
            }
            if decision == .passThrough {
                cancelGesture()
            }
            return eventResponse(for: decision, originalEvent: event)

        case .nativeTitleBarSnap:
            guard activeTarget != nil else {
                return Unmanaged.passUnretained(event)
            }
            updateSnapOverlay(at: event.location, flags: event.flags)
            return Unmanaged.passUnretained(event)

        case .none:
            return Unmanaged.passUnretained(event)
        }
    }

    private func clampMissionControlDragLocation(_ event: CGEvent) {
        MissionControlClamp.apply(event)
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch gestureMode {
        case .dragAnywhere:
            guard activeTarget != nil || dragStrategy.isActive else {
                cancelGesture()
                return Unmanaged.passUnretained(event)
            }
            let target = activeTarget
            let snapAction = snapIntent.commit()
            let decision = dragStrategy.handle(
                .mouseUp(at: event.location, axTrusted: runtime.axTrusted)
            )
            cancelGesture()
            if let target, let snapAction {
                DispatchQueue.main.async { [weak self] in
                    self?.move(target, action: snapAction)
                }
            }
            return eventResponse(for: decision, originalEvent: event)

        case .nativeTitleBarSnap:
            let target = activeTarget
            let action = snapIntent.commit()
            cancelGesture()
            if let target, let action {
                DispatchQueue.main.async { [weak self] in
                    self?.move(target, action: action)
                }
            }
            return Unmanaged.passUnretained(event)

        case .none:
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }
    }

    private func updateSnapOverlay(at location: CGPoint, flags: CGEventFlags) {
        guard runtime.layoutsRuntimeEnabled,
              runtime.settings.allowsDragEdgeSnap(activeModifiers: Self.modifiers(from: flags))
        else {
            activeSnapAction = nil
            snapIntent.reset()
            hideSnapOverlayIfNeeded()
            return
        }

        // Resize-vs-move guard: if the window's size has changed since the
        // gesture began, the user is resizing, not moving — never arm a snap.
        if let initial = initialTargetFrame,
           let current = activeTarget?.element.frame,
           !current.isNull,
           !current.isEmpty {
            let widthChanged = abs(current.width - initial.width) > 4
            let heightChanged = abs(current.height - initial.height) > 4
            if widthChanged || heightChanged {
                activeSnapAction = nil
                snapIntent.reset()
                hideSnapOverlayIfNeeded()
                return
            }
        }

        guard let screen = WindowScreenDetector.current().screen(containing: location) else {
            activeSnapAction = nil
            snapIntent.reset()
            hideSnapOverlayIfNeeded()
            return
        }

        guard let zone = snapIntent.update(at: location, visibleFrame: screen.visibleFrame),
              let action = zone.action,
              let frame = WindowGeometryCalculator().rect(
                  for: action,
                  visibleFrame: screen.visibleFrame
              )
        else {
            activeSnapAction = nil
            hideSnapOverlayIfNeeded()
            return
        }

        activeSnapAction = action
        snapOverlayVisible = true
        let overlayFrame = appKitOverlayFrame(for: frame, screenID: screen.id)
        Task { @MainActor [showSnapOverlay] in showSnapOverlay(overlayFrame) }
    }

    private func appKitOverlayFrame(for cgFrame: CGRect, screenID: UInt32) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { nsScreen in
            (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID
        }) else {
            return cgFrame
        }
        return WindowScreenDetector.convertCGDisplayRectToAppKitCoordinates(
            cgRect: cgFrame,
            appKitScreenFrame: screen.frame,
            cgDisplayBounds: CGDisplayBounds(screenID)
        )
    }

    private func move(_ target: ResolvedWindowTarget, action: WindowAction) {
        let result = mover.move(target.element, action: action)
        let accessibilityElement = target.element as? WindowAccessibilityElement
        let identity = WindowIdentity(
            pid: target.element.processIdentifier,
            cgWindowID: target.windowID,
            titleHash: accessibilityElement?.windowTitleHash,
            frameFingerprint: accessibilityElement?.frameFingerprint
        )
        if let movementHandler {
            Task { @MainActor in
                movementHandler(action, result, identity)
            }
        }
    }

    private func cancelGesture() {
        dragStrategy.cancel()
        snapIntent.reset()
        activeTarget = nil
        activeSnapAction = nil
        initialTargetFrame = nil
        gestureMode = .none
        hideSnapOverlayIfNeeded()
    }

    private func shouldTrackNativeTitleBarSnap(from location: CGPoint, target: ResolvedWindowTarget, flags: CGEventFlags) -> Bool {
        runtime.layoutsRuntimeEnabled
            && runtime.settings.allowsDragEdgeSnap(activeModifiers: Self.modifiers(from: flags))
            && WindowTitleBarDragRegion.contains(location, in: target.element.frame)
    }

    private func performDoubleClickToggle(_ target: ResolvedWindowTarget) {
        // Use the window's native zoom button via AX — this gives the same
        // animated toggle macOS produces when the user double-clicks the title
        // bar with "Zoom" configured in System Settings > Desktop & Dock.
        if let element = target.element as? WindowAccessibilityElement,
           element.performZoomToggle() {
            return
        }

        // Fallback for apps whose zoom button isn't exposed via AX.
        let accessibilityElement = target.element as? WindowAccessibilityElement
        let identity = WindowIdentity(
            pid: target.element.processIdentifier,
            cgWindowID: target.windowID,
            titleHash: accessibilityElement?.windowTitleHash,
            frameFingerprint: accessibilityElement?.frameFingerprint
        )
        if isWindowMaximized(target), let restoreFrame = restoreFrameLookup?(identity) {
            let result = mover.move(target.element, to: restoreFrame, action: .restore)
            if let movementHandler {
                Task { @MainActor in movementHandler(.restore, result, identity) }
            }
        } else {
            move(target, action: .maximize)
        }
    }

    private func isWindowMaximized(_ target: ResolvedWindowTarget) -> Bool {
        let frame = target.element.frame
        guard !frame.isNull, !frame.isEmpty,
              let screen = WindowScreenDetector.current().screen(containing: frame)
        else {
            return false
        }
        let vf = screen.visibleFrame
        let tolerance: CGFloat = 10
        return abs(frame.minX - vf.minX) < tolerance
            && abs(frame.minY - vf.minY) < tolerance
            && abs(frame.maxX - vf.maxX) < tolerance
            && abs(frame.maxY - vf.maxY) < tolerance
    }

    private func beginSnapIntent(at location: CGPoint) {
        activeSnapAction = nil
        guard let screen = WindowScreenDetector.current().screen(containing: location) else {
            snapIntent.reset()
            return
        }
        snapIntent.begin(at: location, visibleFrame: screen.visibleFrame)
    }

    private func hideSnapOverlayIfNeeded() {
        guard snapOverlayVisible else { return }
        snapOverlayVisible = false
        Task { @MainActor [hideSnapOverlay] in hideSnapOverlay() }
    }

    private func isFrontAppIgnored() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return runtime.settings.ignoredBundleIDs.contains(bundleID)
    }

    private func modifier(_ modifier: WindowGestureModifier, isHeldIn flags: CGEventFlags) -> Bool {
        modifier.isSatisfied(by: Self.modifiers(from: flags))
    }

    private func eventResponse(for decision: NativeTitleBarDragDecision, originalEvent event: CGEvent) -> Unmanaged<CGEvent>? {
        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .suppress:
            return nil
        case let .rewrite(type, location):
            return rewrittenEvent(from: event, type: type, location: location)
        case let .replayClick(down, up):
            postReplayedClick(from: event, down: down, up: up)
            return nil
        }
    }

    private func rewrittenEvent(
        from event: CGEvent,
        type: NativeWindowDragOutputEventType,
        location: CGPoint
    ) -> Unmanaged<CGEvent>? {
        guard let rewritten = event.copy() else {
            return nil
        }
        rewritten.type = cgEventType(for: type, originalType: event.type)
        rewritten.location = location
        return Unmanaged.passRetained(rewritten)
    }

    private func postReplayedClick(from event: CGEvent, down: CGPoint, up: CGPoint) {
        guard let mouseDown = event.copy(),
              let mouseUp = event.copy()
        else {
            return
        }
        mouseDown.type = cgEventType(for: .mouseDown, originalType: event.type)
        mouseDown.location = down
        mouseDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)

        mouseUp.type = cgEventType(for: .mouseUp, originalType: event.type)
        mouseUp.location = up
        mouseUp.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }

    private func cgEventType(
        for type: NativeWindowDragOutputEventType,
        originalType: CGEventType
    ) -> CGEventType {
        let isRightMouseEvent = originalType == .rightMouseDown
            || originalType == .rightMouseDragged
            || originalType == .rightMouseUp
        switch (type, isRightMouseEvent) {
        case (.mouseDown, true):
            return .rightMouseDown
        case (.mouseDragged, true):
            return .rightMouseDragged
        case (.mouseUp, true):
            return .rightMouseUp
        case (.mouseDown, false):
            return .leftMouseDown
        case (.mouseDragged, false):
            return .leftMouseDragged
        case (.mouseUp, false):
            return .leftMouseUp
        }
    }

    private func activateTargetForNativeDrag(_ target: ResolvedWindowTarget) {
        let pid = target.element.processIdentifier
        if pid == pid_t(ProcessInfo.processInfo.processIdentifier) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: {
                AppKitWindowIdentifier.matches(windowNumber: $0.windowNumber, cgWindowID: target.windowID)
            }) {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
    }

    private static func modifiers(from flags: CGEventFlags) -> WindowGestureModifier {
        WindowGestureModifier(cgEventFlags: flags)
    }
}

private enum WindowControlEventTapError: LocalizedError {
    case installFailed

    var errorDescription: String? {
        "Could not install the window event tap."
    }
}
