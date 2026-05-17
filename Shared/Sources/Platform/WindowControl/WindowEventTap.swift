import Foundation

public enum WindowEventTapDisabledReason: Equatable, Sendable {
    case timeout
    case userInput
}

public enum WindowEventTapState: Equatable, Sendable {
    case stopped
    case needsAccessibility
    case active
    case recovering(reason: WindowEventTapDisabledReason, retryCount: Int, nextRetryDelay: TimeInterval)
    case error(reason: WindowEventTapDisabledReason)
}

public enum WindowEventTapMouseDownDecision: Equatable, Sendable {
    case passThrough
    case suppress
}

public struct WindowEventTapMouseDownContext: Equatable, Sendable {
    public let enabled: Bool
    public let axTrusted: Bool
    public let coordinatorActive: Bool
    public let recordingHotkey: Bool
    public let modifierHeld: Bool
    public let targetIsNormalNonMAYNWindow: Bool
    public let frontAppIgnored: Bool

    public init(
        enabled: Bool,
        axTrusted: Bool,
        coordinatorActive: Bool,
        recordingHotkey: Bool,
        modifierHeld: Bool,
        targetIsNormalNonMAYNWindow: Bool,
        frontAppIgnored: Bool
    ) {
        self.enabled = enabled
        self.axTrusted = axTrusted
        self.coordinatorActive = coordinatorActive
        self.recordingHotkey = recordingHotkey
        self.modifierHeld = modifierHeld
        self.targetIsNormalNonMAYNWindow = targetIsNormalNonMAYNWindow
        self.frontAppIgnored = frontAppIgnored
    }
}

public final class WindowEventTapStateMachine {
    public private(set) var state: WindowEventTapState = .stopped
    public private(set) var isTapActive = false
    public private(set) var lastFailureReason: WindowEventTapDisabledReason?

    private let maxRetryCount: Int
    private let baseRetryDelay: TimeInterval
    private var failureCount = 0

    public init(maxRetryCount: Int = 3, baseRetryDelay: TimeInterval = 0.5) {
        self.maxRetryCount = max(0, maxRetryCount)
        self.baseRetryDelay = baseRetryDelay
    }

    public func start(enabled: Bool, axTrusted: Bool) {
        failureCount = 0
        applyStart(enabled: enabled, axTrusted: axTrusted)
    }

    public func stop() {
        isTapActive = false
        state = .stopped
    }

    public func retryNow(enabled: Bool, axTrusted: Bool) {
        guard case .recovering = state else {
            return
        }
        applyStart(enabled: enabled, axTrusted: axTrusted)
    }

    public func updateAccessibilityTrust(_ axTrusted: Bool, enabled: Bool) {
        if !enabled {
            stop()
        } else if axTrusted {
            applyStart(enabled: true, axTrusted: true)
        } else {
            isTapActive = false
            state = .needsAccessibility
        }
    }

    public func handleTapDisabled(_ reason: WindowEventTapDisabledReason) {
        guard state == .active, isTapActive else {
            return
        }
        isTapActive = false
        lastFailureReason = reason
        failureCount += 1

        guard failureCount <= maxRetryCount else {
            state = .error(reason: reason)
            return
        }

        state = .recovering(
            reason: reason,
            retryCount: failureCount,
            nextRetryDelay: retryDelay(forRetryCount: failureCount)
        )
    }

    public func handleMouseDown(_ context: WindowEventTapMouseDownContext) -> WindowEventTapMouseDownDecision {
        guard state == .active, isTapActive else {
            return .passThrough
        }
        return Self.shouldSuppressMouseDown(context) ? .suppress : .passThrough
    }

    public static func shouldSuppressMouseDown(_ context: WindowEventTapMouseDownContext) -> Bool {
        context.enabled
            && context.axTrusted
            && context.coordinatorActive
            && !context.recordingHotkey
            && context.modifierHeld
            && context.targetIsNormalNonMAYNWindow
            && !context.frontAppIgnored
    }

    private func applyStart(enabled: Bool, axTrusted: Bool) {
        guard enabled else {
            isTapActive = false
            state = .stopped
            return
        }
        guard axTrusted else {
            isTapActive = false
            state = .needsAccessibility
            return
        }
        isTapActive = true
        state = .active
    }

    private func retryDelay(forRetryCount retryCount: Int) -> TimeInterval {
        baseRetryDelay * pow(2, Double(max(0, retryCount - 1)))
    }
}
