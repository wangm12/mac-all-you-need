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
        restoreDelay: Duration = .milliseconds(450),
        restoreOnManualPasteRequired: Bool = true
    ) async -> PasteInjectionOutcome {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let result = paste(string, into: pasteboard)
        try? await Task.sleep(for: restoreDelay)
        guard result == .injected || restoreOnManualPasteRequired else {
            return PasteInjectionOutcome(result: result, restoredPasteboard: false)
        }
        snapshot.restore(to: pasteboard)
        return PasteInjectionOutcome(result: result, restoredPasteboard: true)
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
