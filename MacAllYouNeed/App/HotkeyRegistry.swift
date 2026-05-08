import Foundation
import Platform

enum HotkeyRegistryError: LocalizedError {
    case duplicate(HotkeyDescriptor)
    case registrationFailed(HotkeyAction, Error)

    var errorDescription: String? {
        switch self {
        case let .duplicate(descriptor):
            return "Duplicate hotkey \(descriptor.display). Pick a unique shortcut."
        case let .registrationFailed(action, error):
            return "Could not register \(action.label): \(error.localizedDescription)"
        }
    }
}

@MainActor
final class HotkeyRegistry {
    private var handles: [HotkeyAction: [GlobalHotkey]] = [:]

    func apply(_ map: [HotkeyAction: [HotkeyDescriptor]], controller: AppController) throws {
        var seen: [HotkeyDescriptor: HotkeyAction] = [:]
        for (action, descriptors) in map {
            for descriptor in descriptors {
                if seen[descriptor] != nil {
                    throw HotkeyRegistryError.duplicate(descriptor)
                }
                seen[descriptor] = action
            }
        }

        var next: [HotkeyAction: [GlobalHotkey]] = [:]
        do {
            for (action, descriptors) in map {
                var registered: [GlobalHotkey] = []
                for descriptor in descriptors {
                    let handle = GlobalHotkey(descriptor: descriptor) { [weak controller] in
                        Task { @MainActor in
                            controller?.performHotkeyAction(action)
                        }
                    }
                    try handle.register()
                    registered.append(handle)
                }
                next[action] = registered
            }
        } catch {
            next.values.flatMap { $0 }.forEach { $0.unregister() }
            let failed = map.keys.first(where: { next[$0] == nil }) ?? .clipboard
            throw HotkeyRegistryError.registrationFailed(failed, error)
        }

        handles.values.flatMap { $0 }.forEach { $0.unregister() }
        handles = next
    }
}
