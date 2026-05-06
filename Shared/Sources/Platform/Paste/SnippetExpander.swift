import AppKit
import Carbon.HIToolbox

public final class SnippetExpander {
    public typealias Lookup = (String) -> String?
    private var tap: CFMachPort?
    private var buffer = ""
    private let lookup: Lookup
    private let triggerStart: Character = ";"

    public init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    public func start() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        let cb: CGEventTapCallBack = { _, _, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<SnippetExpander>.fromOpaque(info).takeUnretainedValue()
            me.handle(event: event)
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: cb, userInfo: context
        )
        if let tap {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); self.tap = nil }
        buffer.removeAll()
    }

    private func handle(event: CGEvent) {
        let maxLen = 16
        var actualLen = 0
        var chars = [UniChar](repeating: 0, count: maxLen)
        event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLen, unicodeString: &chars)
        let str = String(chars.prefix(actualLen).compactMap { Unicode.Scalar($0).map { Character($0) } })
        guard !str.isEmpty else { return }
        for ch in str {
            if ch.isWhitespace || ch.isNewline {
                tryExpand(); buffer.removeAll(); continue
            }
            buffer.append(ch)
            if buffer.count > 64 { buffer.removeFirst(buffer.count - 64) }
        }
    }

    private func tryExpand() {
        guard let start = buffer.firstIndex(of: triggerStart) else { return }
        let candidate = String(buffer[start...])
        guard candidate.count >= 2, let body = lookup(candidate) else { return }
        for _ in 0 ..< (candidate.count + 1) {
            postKey(kVK_Delete)
        }
        PasteInjector.paste(body, mode: .formatted)
    }

    private func postKey(_ vk: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(vk), keyDown: true)?.post(tap: .cgAnnotatedSessionEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(vk), keyDown: false)?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
