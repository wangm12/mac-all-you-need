import Core
import Foundation

/// Runtime and settings copy for the Radial Puck HUD.
enum RadialPuckLabelCopy {
    static func label(
        for selection: RadialSelectionMath.Selection,
        unavailability: RadialMenuCoordinator.Unavailability?
    ) -> String? {
        if let unavailability {
            return label(for: unavailability)
        }
        guard let action = RadialSelectionMath.action(for: selection) else { return nil }
        return label(for: action, selection: selection)
    }

    static func label(for action: WindowAction, selection: RadialSelectionMath.Selection) -> String {
        if selection == .fullScreen {
            return "Fill Screen"
        }
        return RadialMenuSettingsPresentation.actionTitle(action)
    }

    static func label(for unavailability: RadialMenuCoordinator.Unavailability) -> String {
        switch unavailability {
        case .noMovableWindow:
            "No movable window"
        case .accessibilityRequired:
            "Accessibility permission needed"
        case .cannotResize:
            "This window can't be resized"
        }
    }

    static let firstUseHint = "Move around the puck · pull past the ring for Fill Screen"
}
