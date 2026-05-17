import Foundation

public struct WindowControlSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var dragAnywhereEnabled: Bool
    public var dragModifier: WindowGestureModifier
    public var edgeSnapEnabled: Bool
    public var edgeSnapRequiresModifier: Bool
    public var edgeSnapModifier: WindowGestureModifier
    public var doubleClickEnabled: Bool
    public var doubleClickModifier: WindowGestureModifier
    public var ignoredBundleIDs: [String]
    public var titleBarYOffset: Double
    public var debugLoggingEnabled: Bool
    public var showSyntheticClickMarker: Bool

    public init(
        enabled: Bool = false,
        dragAnywhereEnabled: Bool = true,
        dragModifier: WindowGestureModifier = .option,
        edgeSnapEnabled: Bool = true,
        edgeSnapRequiresModifier: Bool = false,
        edgeSnapModifier: WindowGestureModifier = .option,
        doubleClickEnabled: Bool = true,
        doubleClickModifier: WindowGestureModifier = .option,
        ignoredBundleIDs: [String] = [],
        titleBarYOffset: Double = 0,
        debugLoggingEnabled: Bool = false,
        showSyntheticClickMarker: Bool = false
    ) {
        self.enabled = enabled
        self.dragAnywhereEnabled = dragAnywhereEnabled
        self.dragModifier = dragModifier
        self.edgeSnapEnabled = edgeSnapEnabled
        self.edgeSnapRequiresModifier = edgeSnapRequiresModifier
        self.edgeSnapModifier = edgeSnapModifier
        self.doubleClickEnabled = doubleClickEnabled
        self.doubleClickModifier = doubleClickModifier
        self.ignoredBundleIDs = ignoredBundleIDs
        self.titleBarYOffset = titleBarYOffset
        self.debugLoggingEnabled = debugLoggingEnabled
        self.showSyntheticClickMarker = showSyntheticClickMarker
    }

    public static let `default` = WindowControlSettings()

    public var allowsDragEdgeSnap: Bool {
        allowsDragEdgeSnap(activeModifiers: .none)
    }

    public func allowsDragEdgeSnap(activeModifiers: WindowGestureModifier) -> Bool {
        guard edgeSnapEnabled else {
            return false
        }
        guard edgeSnapRequiresModifier else {
            return true
        }
        guard !edgeSnapModifier.isEmpty else {
            return false
        }
        return edgeSnapModifier.isSatisfied(by: activeModifiers)
    }
}
