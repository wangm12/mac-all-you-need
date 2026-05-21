import AppKit
import Foundation

/// Pure-function policy for mapping a keyDown event into a search-query
/// mutation. Used both by the controller's local key monitor and by the
/// dedicated `DockSearchInputController` wrapper below.
///
/// Kept as a separate enum so existing tests that pin character-filtering
/// behavior (`testDockTypingSearch*`) continue to address the pure helper.
enum DockTypingSearch {
    static func updatedQuery(
        current: String,
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let relevantModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let textModifiers: NSEvent.ModifierFlags = [.shift, .capsLock]
        guard relevantModifiers.subtracting(textModifiers).isEmpty else { return nil }

        if keyCode == 51 {
            guard !current.isEmpty else { return nil }
            return String(current.dropLast())
        }

        guard let characters, !characters.isEmpty else { return nil }
        let blockedCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard characters.rangeOfCharacter(from: blockedCharacters) == nil else { return nil }
        return current + characters
    }
}

/// Wraps `DockTypingSearch` for the dock's local key monitor. Given a
/// keyDown event and the current search query, it decides whether to
/// consume the event (returning the new query) or pass it through.
///
/// The controller is intentionally stateless — the caller owns the search
/// query and applies the returned mutation. This keeps the type trivially
/// testable without standing up a `ClipboardDockModel`.
enum DockSearchInputController {
    enum Decision: Equatable {
        /// The event should be consumed and the search query replaced with `newQuery`.
        case consume(newQuery: String)
        /// The event is not a printable character / delete — let it propagate.
        case passthrough
    }

    /// Decide what to do with a keyDown event.
    static func decide(
        currentQuery: String,
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> Decision {
        if let updated = DockTypingSearch.updatedQuery(
            current: currentQuery,
            keyCode: keyCode,
            characters: characters,
            modifiers: modifiers
        ) {
            return .consume(newQuery: updated)
        }
        return .passthrough
    }
}
