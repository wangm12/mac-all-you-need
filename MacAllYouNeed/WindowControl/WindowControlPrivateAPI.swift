import Foundation
import Platform

/// Window-manager private API seam (Sequoia tiling hotkey mitigation).
enum WindowControlPrivateAPI {
    private static let sequoiaTilingHotKey: UInt32 = 79
    private static var sequoiaMitigationApplied = false

    static func applySequoiaTilingMitigation(disabled: Bool) {
        if disabled {
            guard !sequoiaMitigationApplied else { return }
            _ = SystemWindowServerPrivateAPI.shared.setSymbolicHotKeyEnabled(sequoiaTilingHotKey, enabled: false)
            sequoiaMitigationApplied = true
        } else if sequoiaMitigationApplied {
            _ = SystemWindowServerPrivateAPI.shared.setSymbolicHotKeyEnabled(sequoiaTilingHotKey, enabled: true)
            sequoiaMitigationApplied = false
        }
    }
}
