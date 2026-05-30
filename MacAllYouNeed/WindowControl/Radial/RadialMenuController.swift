import AppKit
import Core
import SwiftUI

/// Borderless NSPanel hosting the radial menu, following the same non-activating
/// floating-panel pattern as `WindowSnapOverlayPanel`.
@MainActor
final class RadialMenuController {
    private var panel: NSPanel?
    private let viewModel: RadialMenuViewModel

    init(viewModel: RadialMenuViewModel) {
        self.viewModel = viewModel
    }

    /// `point` is the menu center in AppKit (bottom-left origin) coordinates.
    func show(at point: NSPoint) {
        let size = CGSize(width: 220, height: 220)
        let origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)

        if panel == nil {
            panel = makePanel(origin: origin, size: size)
        }
        guard let panel else { return }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.contentView = NSHostingView(rootView: RadialMenuHost(viewModel: viewModel))
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func makePanel(origin: NSPoint, size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct RadialMenuHost: View {
    @ObservedObject var viewModel: RadialMenuViewModel

    var body: some View {
        RadialMenuView(
            actions: RadialMenuLayout.ringActions,
            selectedIndex: viewModel.selectedRingIndex,
            isCenterSelected: viewModel.isCenterSelected
        )
    }
}
