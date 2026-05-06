import AppKit
import Platform

@MainActor
final class HotkeyController {
    private let popup: ClipboardPopupController
    private var hotkey: GlobalHotkey?

    init(popup: ClipboardPopupController) {
        self.popup = popup
    }

    func registerDefault() {
        try? registerHotkeyThrowing()
    }

    func registerHotkeyThrowing() throws {
        hotkey = GlobalHotkey(descriptor: .defaultClipboard) { [weak self] in
            Task { @MainActor in self?.popup.show() }
        }
        try hotkey?.register()
    }

    func unregister() {
        hotkey?.unregister()
        hotkey = nil
    }
}
