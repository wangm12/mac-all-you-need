import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum PasteMode {
    case formatted
    case plainText
}

public enum PasteResult: String, Equatable, Sendable {
    case injected
    case manualPasteRequired
}

public struct PasteInjectionOutcome: Sendable, Equatable {
    public let result: PasteResult
    public let restoredPasteboard: Bool

    public init(result: PasteResult, restoredPasteboard: Bool) {
        self.result = result
        self.restoredPasteboard = restoredPasteboard
    }
}

public enum PasteInjector {
    @discardableResult
    public static func paste(
        _ string: String?,
        mode: PasteMode = .formatted,
        into pasteboard: NSPasteboard = .general
    ) -> PasteResult {
        if let string {
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        } else if mode == .plainText, let plainText = pasteboard.string(forType: .string) {
            pasteboard.clearContents()
            pasteboard.setString(plainText, forType: .string)
        }
        guard AXIsProcessTrusted() else { return .manualPasteRequired }
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
        return .injected
    }

    public static func pasteWithRestore(
        _ string: String,
        into pasteboard: NSPasteboard = .general,
        restoreDelay: Duration = .milliseconds(200), // ceiling is now hardcoded to 200ms; parameter retained for API compatibility
        restoreOnManualPasteRequired: Bool = true
    ) async -> PasteInjectionOutcome {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let result = paste(string, into: pasteboard)
        if result == .injected || restoreOnManualPasteRequired {
            // Poll until the target app processes the paste (changeCount advances beyond our write),
            // or until the ceiling elapses. Most apps paste within ~30ms; the ceiling matches the
            // previous fixed delay so behaviour is unchanged for slow apps.
            let changeCountAfterWrite = pasteboard.changeCount
            let ceilingNs = UInt64(200_000_000) // 200ms in nanoseconds
            let pollIntervalNs = UInt64(10_000_000) // 10ms
            let deadline = DispatchTime.now().uptimeNanoseconds + ceilingNs
            while DispatchTime.now().uptimeNanoseconds < deadline {
                if pasteboard.changeCount != changeCountAfterWrite { break }
                try? await Task.sleep(nanoseconds: pollIntervalNs)
            }
            snapshot.restore(to: pasteboard)
            return PasteInjectionOutcome(result: result, restoredPasteboard: true)
        }
        return PasteInjectionOutcome(result: result, restoredPasteboard: false)
    }
}

private struct PasteboardSnapshot {
    let items: [[(NSPasteboard.PasteboardType, Data)]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for itemTypes in items {
            let item = NSPasteboardItem()
            for (type, data) in itemTypes {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
