import Foundation

/// Detects when the radial trigger modifier overlaps other window-gesture modifiers.
public enum RadialTriggerConflict {
    public struct Conflict: Equatable, Sendable {
        public let featureName: String
        public let modifier: WindowGestureModifier
    }

    public static func conflicts(in settings: WindowControlSettings) -> [Conflict] {
        let trigger = settings.radialTriggerModifier.normalizedPrimary
        guard !trigger.isEmpty else { return [] }

        var result: [Conflict] = []
        if settings.dragAnywhereEnabled, settings.dragModifier.normalizedPrimary == trigger {
            result.append(Conflict(featureName: "Window Grab", modifier: settings.dragModifier))
        }
        if settings.edgeSnapEnabled,
           !settings.edgeSnapRequiresModifier || settings.edgeSnapModifier.normalizedPrimary == trigger,
           settings.edgeSnapModifier.normalizedPrimary == trigger {
            result.append(Conflict(featureName: "Edge Snap", modifier: settings.edgeSnapModifier))
        }
        if settings.doubleClickEnabled, settings.doubleClickModifier.normalizedPrimary == trigger {
            result.append(Conflict(featureName: "Double-Click Layout", modifier: settings.doubleClickModifier))
        }
        return result
    }
}

private extension WindowGestureModifier {
    var normalizedPrimary: WindowGestureModifier {
        var result: WindowGestureModifier = []
        if contains(.option) || contains(.leftOption) || contains(.rightOption) { result.insert(.option) }
        if contains(.control) || contains(.leftControl) || contains(.rightControl) { result.insert(.control) }
        if contains(.command) || contains(.leftCommand) || contains(.rightCommand) { result.insert(.command) }
        if contains(.shift) || contains(.leftShift) || contains(.rightShift) { result.insert(.shift) }
        return result
    }
}
