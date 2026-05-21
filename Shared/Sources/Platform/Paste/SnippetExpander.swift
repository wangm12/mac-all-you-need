import AppKit
import Carbon.HIToolbox
import Core

public final class SnippetExpander {
    public typealias Lookup = (String) -> String?
    private var tapController: CGEventTapController?
    private var planner: SnippetExpansionPlanner

    public init(
        modeProvider: @escaping () -> SnippetExpansionMode = { SnippetExpansionSettings.load() },
        lookup: @escaping Lookup
    ) {
        planner = SnippetExpansionPlanner(modeProvider: modeProvider, lookup: lookup)
    }

    public func start() {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        let cb: CGEventTapCallBack = { _, _, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<SnippetExpander>.fromOpaque(info).takeUnretainedValue()
            return me.handle(event: event)
        }
        let controller = CGEventTapController(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            runLoop: .current(CFRunLoopGetCurrent()),
            callback: cb,
            userInfo: context
        )
        try? controller.install()
        controller.enable()
        tapController = controller
    }

    public func stop() {
        tapController?.uninstall()
        tapController = nil
        planner.reset()
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let maxLen = 16
        var actualLen = 0
        var chars = [UniChar](repeating: 0, count: maxLen)
        event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLen, unicodeString: &chars)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let rawString = String(chars.prefix(actualLen).compactMap { Unicode.Scalar($0).map { Character($0) } })
        let str = rawString.isEmpty && keyCode == UInt16(kVK_Tab) ? "\t" : rawString
        guard !str.isEmpty else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let hasDisqualifyingModifiers = flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskShift)
        for ch in str {
            if let plan = planner.handle(
                ch,
                keyCode: keyCode,
                hasDisqualifyingModifiers: hasDisqualifyingModifiers
            ) {
                DispatchQueue.main.async { [weak self] in
                    self?.expand(using: plan)
                }
                return plan.suppressCurrentEvent ? nil : Unmanaged.passUnretained(event)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func expand(using plan: SnippetExpansionPlan) {
        for _ in 0 ..< plan.charactersToDelete {
            postKey(kVK_Delete)
        }
        PasteInjector.paste(plan.body, mode: .formatted)
    }

    private func postKey(_ vk: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(vk), keyDown: true)?.post(tap: .cgAnnotatedSessionEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(vk), keyDown: false)?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

struct SnippetExpansionPlan: Equatable {
    let body: String
    let charactersToDelete: Int
    let suppressCurrentEvent: Bool
}

struct SnippetExpansionPlanner {
    typealias Lookup = (String) -> String?

    private var buffer = ""
    private let modeProvider: () -> SnippetExpansionMode
    private let lookup: Lookup
    private let triggerStart: Character = ";"
    private let tabKeyCode = UInt16(kVK_Tab)

    init(
        mode: SnippetExpansionMode = SnippetExpansionSettings.defaultMode,
        lookup: @escaping Lookup
    ) {
        self.init(modeProvider: { mode }, lookup: lookup)
    }

    init(
        modeProvider: @escaping () -> SnippetExpansionMode,
        lookup: @escaping Lookup
    ) {
        self.modeProvider = modeProvider
        self.lookup = lookup
    }

    mutating func handle(
        _ character: Character,
        keyCode: UInt16? = nil,
        hasDisqualifyingModifiers: Bool = false
    ) -> SnippetExpansionPlan? {
        switch modeProvider() {
        case .autoExpand:
            return handleAutoExpand(character)
        case .confirmWithTab:
            return handleConfirmWithTab(
                character,
                keyCode: keyCode,
                hasDisqualifyingModifiers: hasDisqualifyingModifiers
            )
        case .disabled:
            reset()
            return nil
        }
    }

    private mutating func handleAutoExpand(_ character: Character) -> SnippetExpansionPlan? {
        if character.isWhitespace || character.isNewline {
            defer { reset() }
            return expansionPlan()
        }

        appendToBuffer(character)
        return nil
    }

    private mutating func handleConfirmWithTab(
        _ character: Character,
        keyCode: UInt16?,
        hasDisqualifyingModifiers: Bool
    ) -> SnippetExpansionPlan? {
        if keyCode == tabKeyCode {
            defer { reset() }
            guard !hasDisqualifyingModifiers else { return nil }
            return expansionPlan()
        }

        if character.isWhitespace || character.isNewline {
            reset()
            return nil
        }

        appendToBuffer(character)
        return nil
    }

    private mutating func appendToBuffer(_ character: Character) {
        buffer.append(character)
        if buffer.count > 64 { buffer.removeFirst(buffer.count - 64) }
    }

    mutating func reset() {
        buffer.removeAll()
    }

    private func expansionPlan() -> SnippetExpansionPlan? {
        guard let start = buffer.lastIndex(of: triggerStart) else { return nil }
        let candidate = String(buffer[start...])
        guard candidate.count >= 2, let body = lookup(candidate) else { return nil }
        return SnippetExpansionPlan(
            body: body,
            charactersToDelete: candidate.count,
            suppressCurrentEvent: true
        )
    }
}
