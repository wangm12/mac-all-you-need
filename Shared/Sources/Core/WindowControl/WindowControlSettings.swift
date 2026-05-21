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

    /// Bundle IDs that are known to misbehave when their windows are programmatically
    /// resized — typically because they ship their own internal window manager,
    /// reject AX size writes, or restore their own geometry on a timer. Merged into
    /// `ignoredBundleIDs` on first launch only (controlled by `defaultsSeededVersion`),
    /// so user-added or user-removed entries are preserved.
    public static let recommendedIgnoredBundleIDs: [String] = [
        "com.adobe.illustrator",
        "com.adobe.AfterEffects",
        "com.adobe.Photoshop",
        "com.adobe.Premiere Pro.NN",
        "com.mathworks.matlab",
        "com.install4j",
        "com.live2d.cubism.CECubismEditorApp",
        "com.aquafold.datastudio.DataStudio"
    ]

    /// Current version of the recommended-ignored-apps seed. Bump when adding
    /// new entries to `recommendedIgnoredBundleIDs` so existing users pick up
    /// the additions exactly once.
    public static let currentDefaultsSeedVersion = 2

    /// One-shot seed: merges `recommendedIgnoredBundleIDs` into the user's
    /// list, and (in v2) forces `enabled` / `dragAnywhereEnabled` to true now
    /// that the per-feature on/off toggles have been removed from the settings
    /// pages — those gates are owned by the Dashboard feature cards. Skipped
    /// once `defaultsSeededVersion` reaches `currentDefaultsSeedVersion`.
    /// Returns `true` when this call actually changed state.
    @discardableResult
    public mutating func seedRecommendedIgnoredAppsIfNeeded() -> Bool {
        guard defaultsSeededVersion < Self.currentDefaultsSeedVersion else {
            return false
        }
        var existing = Set(ignoredBundleIDs)
        var changed = false
        for bundleID in Self.recommendedIgnoredBundleIDs where !existing.contains(bundleID) {
            existing.insert(bundleID)
            ignoredBundleIDs.append(bundleID)
            changed = true
        }
        // v2: the on/off toggles inside Window Layouts / Window Grab settings
        // pages were removed. The Dashboard's per-feature card is now the only
        // place a user enables/disables these features. Lock both runtime
        // flags to true so the FeatureRuntime gate (featureAvailability) stays
        // the sole source of truth going forward.
        if !enabled {
            enabled = true
            changed = true
        }
        if !dragAnywhereEnabled {
            dragAnywhereEnabled = true
            changed = true
        }
        defaultsSeededVersion = Self.currentDefaultsSeedVersion
        return changed || defaultsSeededVersion != Self.currentDefaultsSeedVersion
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
