import FeatureCore
import Foundation
import Platform

/// Manages the Folder Preview subsystem lifecycle.
///
/// The activatable surface is the Browse Folder global hotkey (⌘⇧F by default).
/// The Quick Look extension is always loaded by the OS regardless of feature state
/// (declared via `osExtensionPolicy` in the descriptor).
///
/// In `testMode`, registration is simulated with a Bool sentinel so tests can run
/// without Carbon hotkey infrastructure.
public actor FolderPreviewFeatureActivator: FeatureActivator {
    private var hotkey: GlobalHotkey?
    // Sentinel used only when testMode == true.
    private var testModeRegistered: Bool = false
    private let testMode: Bool

    /// `true` when the Browse Folder hotkey is registered (real or simulated in testMode).
    public var isHotkeyRegistered: Bool {
        testMode ? testModeRegistered : hotkey != nil
    }

    public init(testMode: Bool = false) {
        self.testMode = testMode
    }

    public func activate() async throws {
        guard !isHotkeyRegistered else { return }

        if testMode {
            testModeRegistered = true
            return
        }

        // Production: register the Browse Folder hotkey.
        // The callback posts a notification so the @MainActor BrowseFolderWindowController
        // can respond without being held here.
        let hk = GlobalHotkey(descriptor: .defaultFolder) {
            NotificationCenter.default.post(name: .browseFolderRequested, object: nil)
        }
        // register() must be called on the main thread (Carbon event system).
        // Capture hk locally and assign to actor-isolated storage after returning.
        try await MainActor.run { try hk.register() }
        hotkey = hk
    }

    public func deactivate() async throws {
        if testMode {
            testModeRegistered = false
            return
        }

        guard let hk = hotkey else { return }
        hotkey = nil
        // unregister() must be called on the main thread.
        await MainActor.run { hk.unregister() }
    }
}
