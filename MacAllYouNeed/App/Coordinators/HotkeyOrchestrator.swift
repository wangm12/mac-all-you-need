import Core
import FeatureCore
import Foundation
import Platform

/// Owns the hotkey registry, the fallback hotkey, and the action dispatch
/// table that maps each `HotkeyAction` to the runtime side-effect it
/// performs (clipboard toggle, browse folder, window control).
///
/// AppController used to inline both the registry plumbing and the
/// dispatch `switch`. Pulling them here lets AppController.performHotkeyAction
/// become a one-line forward, and makes the dispatch table testable in
/// isolation without standing up an entire AppController.
///
/// Hotkey REGISTRATION still flows through `HotkeyRegistry.apply(...)`,
/// which expects an `AppController` so it can route handle callbacks back
/// through `controller.performHotkeyAction(action)`. That route is preserved
/// — the orchestrator is the table the controller forwards through.
@MainActor
final class HotkeyOrchestrator {
    private let onClipboardToggle: () -> Void
    private let onBrowseFolder: () -> Void
    private let onWindowAction: (WindowAction) -> Void
    private let onRadialMenu: () -> Void
    private let onWindowHubToggle: () -> Void

    let registry: HotkeyRegistry
    private var fallbackHotkey: GlobalHotkey?

    init(
        registry: HotkeyRegistry? = nil,
        onClipboardToggle: @escaping () -> Void,
        onBrowseFolder: @escaping () -> Void,
        onWindowAction: @escaping (WindowAction) -> Void,
        onRadialMenu: @escaping () -> Void = {},
        onWindowHubToggle: @escaping () -> Void = {}
    ) {
        self.registry = registry ?? HotkeyRegistry()
        self.onClipboardToggle = onClipboardToggle
        self.onBrowseFolder = onBrowseFolder
        self.onWindowAction = onWindowAction
        self.onRadialMenu = onRadialMenu
        self.onWindowHubToggle = onWindowHubToggle
    }

    /// Translate a `HotkeyAction` into its concrete runtime side-effect.
    /// Mirrors the dispatch table AppController used to inline.
    func performAction(_ action: HotkeyAction) {
        switch action {
        case .clipboard:
            onClipboardToggle()
        case .browseFolder:
            onBrowseFolder()
        case .radialMenu:
            onRadialMenu()
        case .finderHistory:
            break
        case .windowHub:
            onWindowHubToggle()
        case .windowLeftHalf, .windowRightHalf, .windowTopHalf, .windowBottomHalf,
             .windowTopLeft, .windowTopRight, .windowBottomLeft, .windowBottomRight,
             .windowMaximize, .windowAlmostMaximize, .windowCenter, .windowRestore,
             .windowNextDisplay, .windowPreviousDisplay,
             .windowNextSpace, .windowPreviousSpace:
            if let mapped = action.windowAction {
                onWindowAction(mapped)
            }
        }
    }

    /// Apply a hotkey map through the underlying registry. Throws if the
    /// map is invalid or registration fails; caller is responsible for the
    /// fallback path.
    func applyMap(
        _ map: [HotkeyAction: [Platform.HotkeyDescriptor]],
        controller: AppController,
        registerWindowLayoutHotkeys: Bool,
        isFeatureEnabled: @escaping (FeatureID) -> Bool = { _ in true }
    ) throws {
        fallbackHotkey = nil
        try registry.apply(
            map,
            controller: controller,
            registerWindowLayoutHotkeys: registerWindowLayoutHotkeys,
            isFeatureEnabled: isFeatureEnabled
        )
    }

    /// Install the fallback ⌘⇧V clipboard hotkey when normal registration fails.
    func installFallbackHotkey(_ handle: GlobalHotkey) {
        fallbackHotkey = handle
    }

    /// Tear down all registered handles in preparation for hotkey-recording mode.
    /// Mirrors the inline `suspendShortcutTriggersForHotkeyRecording` AppController
    /// previously held.
    func unregisterAll() {
        registry.unregisterAll()
        fallbackHotkey?.unregister()
        fallbackHotkey = nil
    }
}

extension HotkeyAction {
    /// Maps a hotkey action to its corresponding `WindowAction`. Returns nil
    /// for non-window actions (clipboard, browseFolder). Lives here so the
    /// dispatch table in `HotkeyOrchestrator.performAction` reads as a flat
    /// switch.
    var windowAction: WindowAction? {
        switch self {
        case .windowLeftHalf: return .leftHalf
        case .windowRightHalf: return .rightHalf
        case .windowTopHalf: return .topHalf
        case .windowBottomHalf: return .bottomHalf
        case .windowTopLeft: return .topLeft
        case .windowTopRight: return .topRight
        case .windowBottomLeft: return .bottomLeft
        case .windowBottomRight: return .bottomRight
        case .windowMaximize: return .maximize
        case .windowAlmostMaximize: return .almostMaximize
        case .windowCenter: return .center
        case .windowRestore: return .restore
        case .windowNextDisplay: return .nextDisplay
        case .windowPreviousDisplay: return .previousDisplay
        case .windowNextSpace: return .nextSpace
        case .windowPreviousSpace: return .previousSpace
        case .clipboard, .browseFolder, .finderHistory, .radialMenu, .windowHub: return nil
        }
    }
}
