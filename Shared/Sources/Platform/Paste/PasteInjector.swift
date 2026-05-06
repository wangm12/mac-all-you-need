import AppKit
import ApplicationServices
import Carbon.HIToolbox

public enum PasteMode {
    case formatted
    case plainText
}

public enum PasteResult: String, Equatable {
    case injected
    case manualPasteRequired
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
}
