import AppKit
import SwiftUI

struct DockMediaVolumeScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.gesture(
            MagnificationGesture(minimumScaleDelta: 0)
                .onChanged { delta in
                    guard abs(delta - 1) > 0.02 else { return }
                    adjustVolume(delta > 1 ? 1 : -1)
                }
        )
    }

    private func adjustVolume(_ delta: Double) {
        let script = """
        set v to output volume of (get volume settings)
        set output volume to (v + \(Int(delta * 4)))
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}

extension View {
    func dockPreviewMediaVolumeScroll() -> some View {
        modifier(DockMediaVolumeScrollModifier())
    }
}
