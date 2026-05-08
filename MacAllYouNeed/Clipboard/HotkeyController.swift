import AppKit
import Platform

@MainActor
final class HotkeyController {
    private let dock: DockWindowController
    private var hotkey: GlobalHotkey?

    init(dock: DockWindowController) {
        self.dock = dock
    }

    func registerDefault() {
        try? registerHotkeyThrowing()
    }

    func registerHotkeyThrowing() throws {
        hotkey = GlobalHotkey(descriptor: .defaultClipboard) { [weak self] in
            Task { @MainActor in self?.dock.toggle() }
        }
        try hotkey?.register()
    }

    func unregister() {
        hotkey?.unregister()
        hotkey = nil
    }
}
