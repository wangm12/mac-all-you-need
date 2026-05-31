import Core
import Foundation
import Platform

/// Owns the Finder Folder History runtime: the AX recorder, the quick-switcher
/// panel, and the global show-switcher hotkey. AppController drives it via
/// `applyEnabled(_:)` whenever the feature's activation state changes.
@MainActor
final class FolderHistoryRuntime {
    private let store: FolderHistoryStore
    private let recorder: FolderHistoryRecorder
    private let switcher: FolderHistorySwitcherPanel
    private var hotkey: GlobalHotkey?
    private var isActive = false

    init?() {
        guard let store = FolderHistoryStoreLocator.shared() else { return nil }
        self.store = store
        let engine = SystemAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine)
        recorder = FolderHistoryRecorder(store: store, coordinator: coordinator)
        switcher = FolderHistorySwitcherPanel(store: store)
    }

    /// Starts (or stops) recording and the show-switcher hotkey to match the
    /// feature's enabled state. Idempotent.
    func applyEnabled(_ enabled: Bool) {
        guard enabled != isActive else { return }
        isActive = enabled
        if enabled {
            recorder.start()
            registerHotkey()
        } else {
            recorder.stop()
            unregisterHotkey()
            switcher.dismiss()
        }
    }

    /// Re-register the switcher hotkey after the user edits it in settings.
    func reloadHotkey() {
        guard isActive else { return }
        registerHotkey()
    }

    private func registerHotkey() {
        unregisterHotkey()
        let map = HotkeyMapStore.load()
        let descriptors = map[.finderHistory] ?? HotkeyAction.finderHistory.defaultDescriptors
        let descriptor = descriptors.first ?? .defaultFolderHistory
        let hk = GlobalHotkey(descriptor: descriptor) { [weak self] in
            Task { @MainActor in self?.switcher.toggle() }
        }
        try? hk.register()
        hotkey = hk
    }

    private func unregisterHotkey() {
        hotkey?.unregister()
        hotkey = nil
    }
}
