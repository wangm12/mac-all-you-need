import Foundation
import Platform

enum HotkeyRegistryError: LocalizedError {
    case validation(String)
    case duplicate(HotkeyDescriptor)
    case registrationFailed(HotkeyAction, Error)

    var errorDescription: String? {
        switch self {
        case let .validation(message):
            return message
        case let .duplicate(descriptor):
            return "Duplicate hotkey \(descriptor.display). Pick a unique shortcut."
        case let .registrationFailed(action, error):
            return "Could not register \(action.label): \(error.localizedDescription)"
        }
    }
}

enum HotkeyRegistryApplyPlan {
    static func shouldSkipApply(
        next: [HotkeyAction: [HotkeyDescriptor]],
        configured: [HotkeyAction: [HotkeyDescriptor]],
        hasActiveHandles: Bool
    ) -> Bool {
        hasActiveHandles && next == configured
    }
}

@MainActor
final class HotkeyRegistry {
    private var handles: [HotkeyAction: [GlobalHotkey]] = [:]
    private var configuredMap: [HotkeyAction: [HotkeyDescriptor]] = [:]

    func unregisterAll() {
        unregisterHandles()
    }

    func apply(_ map: [HotkeyAction: [HotkeyDescriptor]], controller: AppController) throws {
        if HotkeyRegistryApplyPlan.shouldSkipApply(
            next: map,
            configured: configuredMap,
            hasActiveHandles: !handles.isEmpty
        ) {
            return
        }

        if let issue = HotkeyValidation.firstIssue(
            in: map,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) {
            throw HotkeyRegistryError.validation(issue.message)
        }

        var seen: [HotkeyDescriptor: HotkeyAction] = [:]
        for (action, descriptors) in map {
            for descriptor in descriptors {
                if seen[descriptor] != nil {
                    throw HotkeyRegistryError.duplicate(descriptor)
                }
                seen[descriptor] = action
            }
        }

        var registeringAction: HotkeyAction?
        unregisterHandles()
        do {
            handles = try makeHandles(for: map, controller: controller, registeringAction: &registeringAction)
            configuredMap = map
        } catch {
            unregisterHandles()
            let failed = registeringAction ?? .clipboard
            throw HotkeyRegistryError.registrationFailed(failed, error)
        }
    }

    private func makeHandles(
        for map: [HotkeyAction: [HotkeyDescriptor]],
        controller: AppController,
        registeringAction: inout HotkeyAction?
    ) throws -> [HotkeyAction: [GlobalHotkey]] {
        var next: [HotkeyAction: [GlobalHotkey]] = [:]
        do {
            for action in HotkeyAction.allCases {
                let descriptors = map[action] ?? []
                var registered: [GlobalHotkey] = []
                for descriptor in descriptors {
                    registeringAction = action
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
            return next
        } catch {
            next.values.flatMap { $0 }.forEach { $0.unregister() }
            throw error
        }
    }

    private func unregisterHandles() {
        handles.values.flatMap { $0 }.forEach { $0.unregister() }
        handles = [:]
    }
}
