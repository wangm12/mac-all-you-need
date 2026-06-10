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
    public var radialMenuEnabled: Bool
    public var radialLockToCenter: Bool
    public var radialCursorSelectionEnabled: Bool
    public var radialTriggerModifier: WindowGestureModifier
    /// Number of modifier presses required to open the radial menu (1 = hold once, 2 = double-tap).
    public var radialTriggerTapCount: Int
    public var radialTargetHighlightEnabled: Bool
    public var radialTargetHighlightColor: RadialHighlightColor
    /// When true, pressing the same half shortcut again moves the window to the adjacent display
    /// (Rectangle-style). Defaults to false for predictable dual-monitor behavior.
    public var repeatHalfAcrossDisplays: Bool
    public var snapAssistShowZones: Bool
    public var activeWindowBorderEnabled: Bool
    public var activeWindowBorderInner: Bool
    public var animateWindowMoves: Bool
    public var disableSequoiaTilingHotkeys: Bool
    public var scrollResizeEnabled: Bool
    public var windowRules: [WindowRule]

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
        defaultsSeededVersion: Int = 0,
        radialMenuEnabled: Bool = false,
        radialLockToCenter: Bool = false,
        radialCursorSelectionEnabled: Bool = false,
        radialTriggerModifier: WindowGestureModifier = [.control, .option],
        radialTriggerTapCount: Int = 1,
        radialTargetHighlightEnabled: Bool = true,
        radialTargetHighlightColor: RadialHighlightColor = .focusRingDefault,
        repeatHalfAcrossDisplays: Bool = false,
        snapAssistShowZones: Bool = false,
        activeWindowBorderEnabled: Bool = false,
        activeWindowBorderInner: Bool = true,
        animateWindowMoves: Bool = false,
        disableSequoiaTilingHotkeys: Bool = true,
        scrollResizeEnabled: Bool = false,
        windowRules: [WindowRule] = []
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
        self.radialMenuEnabled = radialMenuEnabled
        self.radialLockToCenter = radialLockToCenter
        self.radialCursorSelectionEnabled = radialCursorSelectionEnabled
        self.radialTriggerModifier = radialTriggerModifier
        self.radialTriggerTapCount = radialTriggerTapCount
        self.radialTargetHighlightEnabled = radialTargetHighlightEnabled
        self.radialTargetHighlightColor = radialTargetHighlightColor
        self.repeatHalfAcrossDisplays = repeatHalfAcrossDisplays
        self.snapAssistShowZones = snapAssistShowZones
        self.activeWindowBorderEnabled = activeWindowBorderEnabled
        self.activeWindowBorderInner = activeWindowBorderInner
        self.animateWindowMoves = animateWindowMoves
        self.disableSequoiaTilingHotkeys = disableSequoiaTilingHotkeys
        self.scrollResizeEnabled = scrollResizeEnabled
        self.windowRules = windowRules
    }

    // Custom decoder so legacy payloads without the radial keys decode with
    // safe `false` defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        dragAnywhereEnabled = try container.decode(Bool.self, forKey: .dragAnywhereEnabled)
        dragModifier = try container.decode(WindowGestureModifier.self, forKey: .dragModifier)
        edgeSnapEnabled = try container.decode(Bool.self, forKey: .edgeSnapEnabled)
        edgeSnapRequiresModifier = try container.decode(Bool.self, forKey: .edgeSnapRequiresModifier)
        edgeSnapModifier = try container.decode(WindowGestureModifier.self, forKey: .edgeSnapModifier)
        doubleClickEnabled = try container.decode(Bool.self, forKey: .doubleClickEnabled)
        doubleClickModifier = try container.decode(WindowGestureModifier.self, forKey: .doubleClickModifier)
        ignoredBundleIDs = try container.decode([String].self, forKey: .ignoredBundleIDs)
        titleBarYOffset = try container.decode(Double.self, forKey: .titleBarYOffset)
        debugLoggingEnabled = try container.decode(Bool.self, forKey: .debugLoggingEnabled)
        showSyntheticClickMarker = try container.decode(Bool.self, forKey: .showSyntheticClickMarker)
        defaultsSeededVersion = try container.decode(Int.self, forKey: .defaultsSeededVersion)
        radialMenuEnabled = try container.decodeIfPresent(Bool.self, forKey: .radialMenuEnabled) ?? false
        radialLockToCenter = try container.decodeIfPresent(Bool.self, forKey: .radialLockToCenter) ?? false
        radialCursorSelectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .radialCursorSelectionEnabled) ?? false
        radialTriggerModifier = try container.decodeIfPresent(WindowGestureModifier.self, forKey: .radialTriggerModifier) ?? [.control, .option]
        radialTriggerTapCount = try container.decodeIfPresent(Int.self, forKey: .radialTriggerTapCount) ?? 1
        radialTargetHighlightEnabled = try container.decodeIfPresent(Bool.self, forKey: .radialTargetHighlightEnabled) ?? true
        radialTargetHighlightColor = try container.decodeIfPresent(RadialHighlightColor.self, forKey: .radialTargetHighlightColor)
            ?? .focusRingDefault
        repeatHalfAcrossDisplays = try container.decodeIfPresent(Bool.self, forKey: .repeatHalfAcrossDisplays) ?? false
        snapAssistShowZones = try container.decodeIfPresent(Bool.self, forKey: .snapAssistShowZones) ?? false
        activeWindowBorderEnabled = try container.decodeIfPresent(Bool.self, forKey: .activeWindowBorderEnabled) ?? false
        activeWindowBorderInner = try container.decodeIfPresent(Bool.self, forKey: .activeWindowBorderInner) ?? true
        animateWindowMoves = try container.decodeIfPresent(Bool.self, forKey: .animateWindowMoves) ?? false
        disableSequoiaTilingHotkeys = try container.decodeIfPresent(Bool.self, forKey: .disableSequoiaTilingHotkeys) ?? true
        scrollResizeEnabled = try container.decodeIfPresent(Bool.self, forKey: .scrollResizeEnabled) ?? false
        windowRules = try container.decodeIfPresent([WindowRule].self, forKey: .windowRules) ?? []
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
