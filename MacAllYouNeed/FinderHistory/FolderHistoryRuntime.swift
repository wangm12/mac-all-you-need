import ApplicationServices
import Core
import Foundation
import Platform

/// Owns Finder Folder History: AX recorder, hotkey history panel, and global hotkey.
@MainActor
final class FolderHistoryRuntime {
    private let store: FolderHistoryStore
    private let recorder: FolderHistoryRecorder
    private let switcher: FolderHistorySwitcherPanel
    private var hotkey: GlobalHotkey?
    private var isRecordingEnabled = false
    private let log = Logging.logger(for: "folder-history", category: "runtime")

    init?(historyWorker: FolderHistoryFeatureWorker? = nil) {
        guard let store = FolderHistoryStoreLocator.shared() else { return nil }
        self.store = store
        let engine = SystemAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine)
        recorder = FolderHistoryRecorder(
            store: store,
            coordinator: coordinator,
            historyWorker: historyWorker
        )
        switcher = FolderHistorySwitcherPanel(store: store)
        registerHotkey()
    }

    func applyEnabled(_ enabled: Bool) {
        guard enabled != isRecordingEnabled else { return }
        isRecordingEnabled = enabled
        if enabled {
            recorder.start()
        } else {
            recorder.stop()
            switcher.dismiss()
        }
    }

    func reloadHotkey() {
        registerHotkey()
    }

    func panelContext() -> FolderHistoryPanelContext {
        let settings = FolderHistorySettingsStore.load()
        return FolderHistoryPanelContext(
            isFeatureEnabled: isRecordingEnabled,
            isAccessibilityGranted: AXIsProcessTrusted(),
            isPaused: settings.isPaused
        )
    }

    private func registerHotkey() {
        unregisterHotkey()
        let map = HotkeyMapStore.load()
        let descriptors = map[.finderHistory] ?? HotkeyAction.finderHistory.defaultDescriptors
        let descriptor = descriptors.first ?? .defaultFolderHistory
        let hk = GlobalHotkey(descriptor: descriptor) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.switcher.show(context: self.panelContext())
            }
        }
        do {
            try hk.register()
            hotkey = hk
        } catch {
            log.error("Failed to register folder history hotkey: \(error.localizedDescription, privacy: .public)")
            hotkey = nil
        }
    }

    private func unregisterHotkey() {
        hotkey?.unregister()
        hotkey = nil
    }
}
