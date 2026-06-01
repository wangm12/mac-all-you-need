import AppKit
import SwiftUI

/// Material panel background (DockDoor `BlurView` / `dockStyle` subset).
struct DockPreviewVisualEffectBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var opacity: Double
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.alphaValue = opacity
        nsView.layer?.cornerRadius = cornerRadius
    }
}
