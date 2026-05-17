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

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var runtime = Runtime()
    private var activeTarget: ResolvedWindowTarget?
    private var activeSnapAction: WindowAction?
    private var gestureMode: GestureMode = .none
    private var snapOverlayVisible = false
    private let stateMachine = WindowEventTapStateMachine()
    private let resolver: WindowTargetResolver
    private let mover: WindowMover
    private let dragStrategy: NativeTitleBarDragStrategy
    private var movementHandler: (@MainActor (WindowAction, WindowMovementResult, WindowIdentity?) -> Void)?
    private var showSnapOverlay: @MainActor (CGRect) -> Void = { _ in }
    private var hideSnapOverlay: @MainActor () -> Void = {}

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
        eventTap != nil
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
        guard eventTap == nil else { return }
        stateMachine.start(enabled: runtime.anyRuntimeBehaviorEnabled, axTrusted: runtime.axTrusted)

        let mouseMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let recoveryMask = CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        let mask = mouseMask | recoveryMask
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<WindowControlEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            throw WindowControlEventTapError.installFailed
        }

        eventTap = tap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        cancelGesture()
        stateMachine.stop()
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
            stateMachine.handleTapDisabled(type == .tapDisabledByTimeout ? .timeout : .userInput)
            if case .recovering = stateMachine.state, let eventTap {
                stateMachine.retryNow(enabled: runtime.anyRuntimeBehaviorEnabled, axTrusted: runtime.axTrusted)
                if stateMachine.isTapActive {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
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
                gestureMode = .nativeTitleBarSnap
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

        if doubleClickModifierHeld {
            move(target, action: .maximize)
            cancelGesture()
            return nil
        }

        guard dragModifierHeld else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }

        _ = dragStrategy.handle(
            .mouseDown(at: location, axTrusted: runtime.axTrusted),
            target: target.element
        )
        guard dragStrategy.isActive else {
            cancelGesture()
            return Unmanaged.passUnretained(event)
        }
        gestureMode = .dragAnywhere
        return nil
    }

    private func handleMouseDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch gestureMode {
        case .dragAnywhere:
            guard activeTarget != nil, dragStrategy.isActive else {
                return Unmanaged.passUnretained(event)
            }
            let decision = dragStrategy.handle(
                .mouseDragged(to: event.location, axTrusted: runtime.axTrusted)
            )
            if decision == .suppress {
                updateSnapOverlay(at: event.location, flags: event.flags)
            } else {
                hideSnapOverlayIfNeeded()
            }
            return decision == .suppress ? nil : Unmanaged.passUnretained(event)

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

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch gestureMode {
        case .dragAnywhere:
            guard activeTarget != nil || dragStrategy.isActive else {
                cancelGesture()
                return Unmanaged.passUnretained(event)
            }
            if let target = activeTarget, let action = activeSnapAction {
                move(target, action: action)
            }
            let decision = dragStrategy.handle(
                .mouseUp(at: event.location, axTrusted: runtime.axTrusted)
            )
            cancelGesture()
            return decision == .suppress ? nil : Unmanaged.passUnretained(event)

        case .nativeTitleBarSnap:
            let target = activeTarget
            let action = activeSnapAction
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
            hideSnapOverlayIfNeeded()
            return
        }

        guard let screen = WindowScreenDetector.current().screen(containing: location) else {
            activeSnapAction = nil
            hideSnapOverlayIfNeeded()
            return
        }

        let zone = WindowSnapZone.zone(for: location, in: screen.visibleFrame)
        guard let action = zone.action,
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
        activeTarget = nil
        activeSnapAction = nil
        gestureMode = .none
        hideSnapOverlayIfNeeded()
    }

    private func shouldTrackNativeTitleBarSnap(from location: CGPoint, target: ResolvedWindowTarget, flags: CGEventFlags) -> Bool {
        runtime.layoutsRuntimeEnabled
            && runtime.settings.allowsDragEdgeSnap(activeModifiers: Self.modifiers(from: flags))
            && WindowTitleBarDragRegion.contains(location, in: target.element.frame)
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
