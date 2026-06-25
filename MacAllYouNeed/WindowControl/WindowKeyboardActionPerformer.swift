import AppKit
import ApplicationServices
import Core
import Platform

@MainActor
final class WindowKeyboardActionPerformer: WindowControlActionPerforming {
    private struct ResolvedWindow {
        let element: WindowAccessibilityElement
        let snapshot: WindowSnapshot
        let identity: WindowIdentity
    }

    private struct SettlingMove {
        let identity: WindowIdentity
        let startedAt: Date
    }

    private let mover: WindowMover
    private var pendingWindow: ResolvedWindow?
    private var previousResult: WindowMovementResult?
    private var previousIdentity: WindowIdentity?
    private var settlingMove: SettlingMove?
    private let now: () -> Date

    var repeatHalfAcrossDisplays: Bool {
        get { mover.repeatHalfAcrossDisplays }
        set { mover.repeatHalfAcrossDisplays = newValue }
    }

    var animateMoves: Bool {
        get { mover.animateMoves }
        set { mover.animateMoves = newValue }
    }

    var animationConfiguration: WindowMoveAnimationConfiguration {
        get { mover.animationConfiguration }
        set { mover.animationConfiguration = newValue }
    }

    var onAnimatedMoveFinished: ((WindowMovementResult) -> Void)? {
        get { mover.onAnimatedMoveFinished }
        set { mover.onAnimatedMoveFinished = newValue }
    }

    var lastAnimatedMoveGeneration: Int {
        mover.lastAnimatedMoveGeneration
    }

    func setAnimatedMoveCompletion(
        for generation: Int,
        handler: @escaping (WindowMovementResult) -> Void
    ) {
        mover.setAnimatedMoveCompletion(for: generation, handler: handler)
    }

    init(mover: WindowMover = WindowMover(), now: @escaping () -> Date = Date.init) {
        self.mover = mover
        self.now = now
    }

    var currentIdentity: WindowIdentity? {
        let resolveSignpost = PerformanceSignpost.WindowControl.beginResolveWindow()
        defer { PerformanceSignpost.WindowControl.endResolveWindow(resolveSignpost) }
        let resolved = resolveFocusedWindow()
        pendingWindow = resolved
        return resolved?.identity
    }

    func perform(_ action: WindowAction, restoreFrame: CGRect?) -> WindowMovementResult? {
        let resolveSignpost = PerformanceSignpost.WindowControl.beginResolveWindow()
        let resolved = pendingWindow ?? resolveFocusedWindow()
        pendingWindow = nil
        PerformanceSignpost.WindowControl.endResolveWindow(resolveSignpost)
        guard let resolved else { return nil }

        let currentDate = now()
        if let settlingMove,
           resolved.identity.matchesSameWindow(as: settlingMove.identity),
           WindowMoveCoalescing.shouldSupersedeInFlightMove(
               sameWindow: true,
               inFlightStartedAt: settlingMove.startedAt,
               now: currentDate
           )
        {
            mover.cancelPendingCrossDisplayRetry()
            mover.cancelInFlightMoveAnimation()
        }

        defer {
            settlingMove = SettlingMove(identity: resolved.identity, startedAt: now())
        }

        #if DEBUG
        WindowAccessibilityElement.countsAXOperations = true
        let axCountStart = WindowAccessibilityElement.debugAXOperationCount
        #endif
        let started = CFAbsoluteTimeGetCurrent()

        let calculateSignpost = PerformanceSignpost.WindowControl.beginCalculateFrame(action: action.rawValue)
        let result: WindowMovementResult?
        if action == .restore, let restoreFrame {
            result = mover.move(resolved.element, to: restoreFrame, action: action)
        } else {
            result = mover.move(
                resolved.element,
                snapshot: resolved.snapshot,
                action: action,
                previousResult: resolved.identity.matchesSameWindow(as: previousIdentity) ? previousResult : nil
            )
        }
        PerformanceSignpost.WindowControl.endCalculateFrame(calculateSignpost)

        let durationMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
        #if DEBUG
        let axRoundTrips = WindowAccessibilityElement.debugAXOperationCount - axCountStart
        WindowControlMoveDiagnostics.record(axRoundTrips: axRoundTrips, durationMilliseconds: durationMs)
        #else
        WindowControlMoveDiagnostics.record(axRoundTrips: 0, durationMilliseconds: durationMs)
        #endif

        if let result {
            previousResult = result
            previousIdentity = resolved.identity
        }
        return result
    }

    private func resolveFocusedWindow() -> ResolvedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let axWindow = value,
              CFGetTypeID(axWindow) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let axElement = axWindow as! AXUIElement
        let element = WindowAccessibilityElement(axElement)
        let snap = element.snapshot()
        guard snap.isSupportedForWindowControl else {
            return nil
        }
        return ResolvedWindow(
            element: element,
            snapshot: snap,
            identity: WindowIdentity(
                pid: element.processIdentifier,
                cgWindowID: WindowCGWindowMatcher.windowID(
                    forProcessIdentifier: element.processIdentifier,
                    frame: snap.frame
                ),
                titleHash: element.windowTitleHash,
                frameFingerprint: WindowAccessibilityElement.frameFingerprint(for: snap.frame)
            )
        )
    }
}

private extension WindowIdentity {
    func matchesSameWindow(as other: WindowIdentity?) -> Bool {
        guard let other, pid == other.pid else {
            return false
        }
        if let cgWindowID, let otherCGWindowID = other.cgWindowID {
            return cgWindowID == otherCGWindowID
        }
        if let titleHash, let otherTitleHash = other.titleHash {
            return titleHash == otherTitleHash
        }
        return frameFingerprint == other.frameFingerprint
    }
}
