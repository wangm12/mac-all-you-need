import FeatureCore

/// Manages the Folder Preview subsystem lifecycle.
///
/// The Quick Look extension is always loaded by the OS regardless of feature state
/// (declared via `osExtensionPolicy` in the descriptor), and the Browse Folder
/// shortcut is owned by AppController's HotkeyRegistry with the other app hotkeys.
public actor FolderPreviewFeatureActivator: FeatureActivator {
    private var isActive: Bool = false

    /// Folder Preview does not own the Browse Folder hotkey; AppController's HotkeyRegistry does.
    public var isHotkeyRegistered: Bool {
        false
    }

    public init(testMode: Bool = false) {}

    public func activate() async throws {
        guard !isActive else { return }
        isActive = true
    }

    public func deactivate() async throws {
        isActive = false
    }
}
