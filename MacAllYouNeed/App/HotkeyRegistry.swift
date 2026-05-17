import FeatureCore
import Foundation
import Platform

enum HotkeyRegistryError: LocalizedError {
    case validation(String)
    case duplicate(Platform.HotkeyDescriptor)
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
        next: [HotkeyAction: [Platform.HotkeyDescriptor]],
        configured: [HotkeyAction: [Platform.HotkeyDescriptor]],
        hasActiveHandles: Bool
    ) -> Bool {
        hasActiveHandles && next == configured
    }
}

enum HotkeyRegistryRegistrationPlan {
    static func activeMap(
        from map: [HotkeyAction: [Platform.HotkeyDescriptor]],
        windowControlEnabled: Bool,
        windowActionPerformerAvailable: Bool = false
    ) -> [HotkeyAction: [Platform.HotkeyDescriptor]] {
        map.filter { action, _ in
            !action.isWindowControlAction || (windowControlEnabled && windowActionPerformerAvailable)
        }
    }
}

@MainActor
final class HotkeyRegistry {
    private var handles: [HotkeyAction: [GlobalHotkey]] = [:]
    private var configuredMap: [HotkeyAction: [Platform.HotkeyDescriptor]] = [:]

    func unregisterAll() {
        unregisterHandles()
    }

    func apply(
        _ map: [HotkeyAction: [Platform.HotkeyDescriptor]],
        controller: AppController,
        windowControlEnabled: Bool = WindowControlSettingsStore.load().enabled,
        windowActionPerformerAvailable: Bool = false
    ) throws {
        let activeMap = HotkeyRegistryRegistrationPlan.activeMap(
            from: map,
            windowControlEnabled: windowControlEnabled,
            windowActionPerformerAvailable: windowActionPerformerAvailable
        )
        if HotkeyRegistryApplyPlan.shouldSkipApply(
            next: activeMap,
            configured: configuredMap,
            hasActiveHandles: !handles.isEmpty
        ) {
            return
        }

        if let issue = HotkeyValidation.firstIssue(
            in: activeMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) {
            throw HotkeyRegistryError.validation(issue.message)
        }

        var seen: [Platform.HotkeyDescriptor: HotkeyAction] = [:]
        for (action, descriptors) in activeMap {
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
            handles = try makeHandles(for: activeMap, controller: controller, registeringAction: &registeringAction)
            configuredMap = activeMap
        } catch {
            unregisterHandles()
            let failed = registeringAction ?? .clipboard
            throw HotkeyRegistryError.registrationFailed(failed, error)
        }
    }

    private func makeHandles(
        for map: [HotkeyAction: [Platform.HotkeyDescriptor]],
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

    // MARK: - Registry-driven enumeration (Phase 04)

    /// Returns all hotkey metadata declared by features in `registry`, in registry order.
    /// Consumed by HotkeysSettingsView (Phase 05) to display per-feature hotkey entries.
    func declaredHotkeys(from registry: FeatureRegistry) -> [(FeatureID, FeatureCore.HotkeyDescriptor)] {
        registry.descriptors.flatMap { descriptor in
            descriptor.hotkeys.map { (descriptor.id, $0) }
        }
    }
}
