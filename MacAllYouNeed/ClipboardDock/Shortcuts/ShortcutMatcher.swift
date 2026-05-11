import AppKit

@MainActor
enum ShortcutMatcher {
    static func matches(_ event: NSEvent, _ action: ShortcutAction, registry: ShortcutRegistry) -> Bool {
        registry.matches(event: event, action)
    }
}
