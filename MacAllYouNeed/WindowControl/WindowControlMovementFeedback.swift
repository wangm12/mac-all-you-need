import AppKit
import Core
import Platform

@MainActor
enum WindowControlMovementFeedback {
    private static var lastMessage: String?
    private static var lastShownAt: Date?
    private static let debounceInterval: TimeInterval = 2

    static func present(status: WindowMovementStatus, axTrusted: Bool, now: Date = Date()) {
        guard let message = message(for: status, axTrusted: axTrusted) else { return }
        if lastMessage == message,
           let lastShownAt,
           now.timeIntervalSince(lastShownAt) < debounceInterval
        {
            return
        }
        lastMessage = message
        lastShownAt = now
        let symbol = symbol(for: status)
        CopyHUD.show(message, symbol: symbol)
    }

    #if DEBUG
    static func resetForTesting() {
        lastMessage = nil
        lastShownAt = nil
    }
    #endif

    static func message(for status: WindowMovementStatus, axTrusted: Bool) -> String? {
        switch status {
        case .fixedSizeWindow:
            return "This window can't be resized"
        case .writeFailed:
            if axTrusted {
                return "Couldn't move this window"
            }
            return "Couldn't move this window — check Accessibility permission"
        case .unsupportedWindow:
            return "This window can't be moved with Window Layouts"
        case .moved, .noDisplay, .noTargetFrame:
            return nil
        }
    }

    static func symbol(for status: WindowMovementStatus) -> String {
        switch status {
        case .fixedSizeWindow, .unsupportedWindow:
            "rectangle.slash"
        case .writeFailed:
            "exclamationmark.triangle.fill"
        case .moved, .noDisplay, .noTargetFrame:
            "info.circle.fill"
        }
    }
}
