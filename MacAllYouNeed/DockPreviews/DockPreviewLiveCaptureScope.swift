import CoreGraphics
import Foundation

enum DockPreviewLiveCaptureScope {
    static func windowIDs(
        windows: [DockPreviewWindowEntry],
        selectedIndex: Int,
        scope: DockLivePreviewScope
    ) -> [CGWindowID] {
        let real = windows.filter { !$0.title.isEmpty && $0.title != "No open windows" }
        guard !real.isEmpty else { return [] }
        guard selectedIndex >= 0, selectedIndex < windows.count else {
            return real.map(\.id)
        }
        switch scope {
        case .selectedWindowOnly:
            return [windows[selectedIndex].id]
        case .selectedAppWindows:
            let pid = windows[selectedIndex].pid
            return real.filter { $0.pid == pid }.map(\.id)
        case .allWindows:
            return real.map(\.id)
        }
    }
}
