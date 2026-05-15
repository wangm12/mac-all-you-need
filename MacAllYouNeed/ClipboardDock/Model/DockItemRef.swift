import AppKit
import Foundation
import UniformTypeIdentifiers

enum DockDragPayloadTypes {
    static let acceptedTypeIdentifiers: [String] = [
        UTType.text.identifier,
        UTType.plainText.identifier,
        UTType.utf8PlainText.identifier
    ]

    static let acceptedPasteboardTypes: [NSPasteboard.PasteboardType] =
        ([.string] + acceptedTypeIdentifiers.map { NSPasteboard.PasteboardType($0) })
}

enum DockDragPayloadLoader {
    static func strings(from providers: [NSItemProvider], completion: @escaping ([String]) -> Void) {
        let accumulator = StringAccumulator()
        let group = DispatchGroup()

        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                group.enter()
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    accumulator.append(object)
                    group.leave()
                }
                continue
            }

            guard let type = DockDragPayloadTypes.acceptedTypeIdentifiers.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else { continue }

            group.enter()
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                accumulator.append(item)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.values)
        }
    }
}

private final class StringAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ object: Any?) {
        let string: String?
        switch object {
        case let value as String:
            string = value
        case let value as NSString:
            string = value as String
        case let data as Data:
            string = String(data: data, encoding: .utf8)
        default:
            string = nil
        }

        guard let string else { return }
        lock.lock()
        storage.append(string)
        lock.unlock()
    }
}

/// Internal drag payload encoded as a String so we don't have to register a
/// custom UTI in Info.plist (which `UTType(exportedAs:)` expects). The
/// "dockitem://" marker prefix lets tabs filter out unrelated text drags.
enum DockItemDrag {
    static let prefix = "dockitem://"

    /// Encode `item.id` (preview is intentionally not included so external
    /// text drops onto Notes/etc don't see our marker; that path will use
    /// the inner card's content draggable when we re-add it).
    static func encode(recordID: String) -> String {
        prefix + recordID
    }

    static func decode(_ raw: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let id = String(raw.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// Drag payload for reordering user-created pinboard tabs. Uses the same
/// String + marker-prefix scheme as `DockItemDrag` so the tab's drop handler
/// can dispatch on prefix and not confuse a tab-reorder drag with an item-pin
/// drag.
enum DockTabDrag {
    static let prefix = "pinboardtab://"

    static func encode(boardID: String) -> String {
        prefix + boardID
    }

    static func decode(_ raw: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let id = String(raw.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }
}

/// Sent by `CardContextMenu` when the user picks "Paste to <App>" or
/// "Paste as Plain Text". `DockWindowController` observes it and routes
/// through `triggerPaste(at:modifiers:)` so the dock dismiss + focus-restore
/// + delay logic in `DockPasteCoordinator` is reused.
struct DockPasteIntent {
    let itemID: String
    let plainText: Bool
}

extension Notification.Name {
    static let dockPasteRequested = Notification.Name("dockPasteRequested")
    /// Posted by views inside the dock when an action (e.g. double-click
    /// copy) wants to dismiss the panel without going through the responder
    /// chain. The DockWindowController observes during its visible window.
    static let dockHideRequested = Notification.Name("dockHideRequested")
}
