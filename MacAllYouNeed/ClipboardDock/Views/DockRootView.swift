import AppKit
import SwiftUI

struct DockRootView: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    let dismiss: () -> Void
    let onPaste: (Int, Bool) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DockTopBar(model: model, openSettings: openSettings)
            Divider()
            ClipCarousel(
                model: model,
                favicons: favicons,
                registry: registry,
                onPaste: onPaste
            )
            .frame(maxHeight: .infinity)
        }
        .background(
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedCorners(radius: 12, corners: [.topLeft, .topRight]))
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: NSRectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tr),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bl),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tl, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        return path
    }
}

private struct NSRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = NSRectCorner(rawValue: 1 << 0)
    static let topRight = NSRectCorner(rawValue: 1 << 1)
    static let bottomLeft = NSRectCorner(rawValue: 1 << 2)
    static let bottomRight = NSRectCorner(rawValue: 1 << 3)
}
