import Foundation
import Platform

/// Window-manager private API seam (Sequoia tiling hotkey mitigation).
enum WindowControlPrivateAPI {
    private static let sequoiaTilingHotKey: UInt32 = 79

    static func applySequoiaTilingMitigation(disabled: Bool) {
        guard disabled else { return }
        _ = SystemWindowServerPrivateAPI.shared.setSymbolicHotKeyEnabled(sequoiaTilingHotKey, enabled: false)
    }
}
