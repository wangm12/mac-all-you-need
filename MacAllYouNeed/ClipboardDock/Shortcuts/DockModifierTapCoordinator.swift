import Foundation
import Platform

/// Registers in-dock modifier-tap shortcuts with the global `ModifierTapDispatcher`
/// while the clipboard dock is visible. Callbacks are gated on dock activity.
@MainActor
final class DockModifierTapCoordinator {
    private let registry: ShortcutRegistry
    private let isActive: () -> Bool
    private let perform: (ShortcutAction) -> Void
    private var tokens: [ModifierTapDispatcher.Token] = []

    init(
        registry: ShortcutRegistry,
        isActive: @escaping () -> Bool,
        perform: @escaping (ShortcutAction) -> Void
    ) {
        self.registry = registry
        self.isActive = isActive
        self.perform = perform
    }

    func sync() {
        stop()
        for action in ShortcutAction.allCases {
            for descriptor in registry.modifierTapBindings(for: action) {
                guard let tap = descriptor.modifierTap else { continue }
                let token = ModifierTapDispatcher.shared.register(tap) { [weak self] in
                    guard let self, self.isActive() else { return }
                    self.perform(action)
                }
                tokens.append(token)
            }
        }
    }

    func start() {
        sync()
    }

    func stop() {
        for token in tokens {
            ModifierTapDispatcher.shared.unregister(token)
        }
        tokens.removeAll()
    }
}
