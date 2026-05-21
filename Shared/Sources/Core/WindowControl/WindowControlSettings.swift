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
    public var defaultsSeededVersion: Int

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
        showSyntheticClickMarker: Bool = false,
        defaultsSeededVersion: Int = 0
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
        self.defaultsSeededVersion = defaultsSeededVersion
    }

    public static let `default` = WindowControlSettings()

    /// Bundle IDs that were auto-seeded in v1 and should be removed in v3.
    /// These apps are rarely installed by typical users and were added by mistake.
    private static let v1SeededBundleIDs: Set<String> = [
        "com.adobe.illustrator",
        "com.adobe.AfterEffects",
        "com.adobe.Photoshop",
        "com.adobe.Premiere Pro.NN",
        "com.mathworks.matlab",
        "com.install4j",
        "com.live2d.cubism.CECubismEditorApp",
        "com.aquafold.datastudio.DataStudio"
    ]

    /// Bundle IDs that are known to misbehave when their windows are programmatically
    /// resized. Now empty — users should add their own via the Ignored Apps UI.
    public static let recommendedIgnoredBundleIDs: [String] = []

    /// Current version of the recommended-ignored-apps seed.
    public static let currentDefaultsSeedVersion = 3

    /// One-shot migration. Returns `true` when state changed.
    @discardableResult
    public mutating func seedRecommendedIgnoredAppsIfNeeded() -> Bool {
        guard defaultsSeededVersion < Self.currentDefaultsSeedVersion else {
            return false
        }
        var changed = false

        // v2: force enabled/dragAnywhereEnabled = true
        if !enabled { enabled = true; changed = true }
        if !dragAnywhereEnabled { dragAnywhereEnabled = true; changed = true }

        // v3: remove the apps auto-seeded in v1 that the user never chose
        let before = ignoredBundleIDs.count
        ignoredBundleIDs = ignoredBundleIDs.filter { !Self.v1SeededBundleIDs.contains($0) }
        if ignoredBundleIDs.count != before { changed = true }

        defaultsSeededVersion = Self.currentDefaultsSeedVersion
        return changed
    }

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
