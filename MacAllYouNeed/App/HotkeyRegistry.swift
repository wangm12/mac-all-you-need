import Foundation
import Platform

enum HotkeyRegistryError: LocalizedError {
    case duplicate(HotkeyDescriptor)
    case registrationFailed(HotkeyAction, Error)

    var errorDescription: String? {
        switch self {
        case .duplicate(let d): return "Duplicate hotkey \(d.display). Pick a unique shortcut."
        case .registrationFailed(let a, let e): return "Could not register \(a.label): \(e.localizedDescription)"
        }
    }
}

@MainActor
final class HotkeyRegistry {
    private var handles: [HotkeyAction: GlobalHotkey] = [:]

    func apply(_ map: [HotkeyAction: HotkeyDescriptor], controller: AppController) throws {
        var seen: [HotkeyDescriptor: HotkeyAction] = [:]
        for (action, descriptor) in map {
            if seen[descriptor] != nil { throw HotkeyRegistryError.duplicate(descriptor) }
            seen[descriptor] = action
        }
        var next: [HotkeyAction: GlobalHotkey] = [:]
        do {
            for (action, descriptor) in map {
                let handle = GlobalHotkey(descriptor: descriptor) { [weak controller] in
                    Task { @MainActor in controller?.performHotkeyAction(action) }
                }
                try handle.register()
                next[action] = handle
            }
        } catch {
            next.values.forEach { $0.unregister() }
            let failed = map.first { next[$0.key] == nil }?.key ?? .clipboard
            throw HotkeyRegistryError.registrationFailed(failed, error)
        }
        handles.values.forEach { $0.unregister() }
        handles = next
    }
}
