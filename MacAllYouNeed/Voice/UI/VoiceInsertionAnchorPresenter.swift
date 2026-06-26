import AppKit
import SwiftUI
import UI

/// Optional mic glyph anchor near the text insertion point (not a full hover bar).
@MainActor
final class VoiceInsertionAnchorPresenter {
    private var panelController: NonActivatingFloatingPanelController<VoiceInsertionAnchorView>?

    func showNearMouse() {
        let view = VoiceInsertionAnchorView()
        let size = CGSize(width: 20, height: 20)
        if panelController == nil {
            panelController = NonActivatingFloatingPanelController<VoiceInsertionAnchorView>(
                styleMask: [.borderless, .nonactivatingPanel],
                level: VoiceHUDWindowLayering.windowLevel,
                collectionBehavior: VoiceHUDWindowLayering.collectionBehavior,
                hasShadow: false,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut),
                positioner: { panel, panelSize in
                    let mouse = NSEvent.mouseLocation
                    panel.setFrameOrigin(NSPoint(x: mouse.x - panelSize.width / 2, y: mouse.y + 12))
                }
            )
        }
        panelController?.present(rootView: view, size: size, animated: true)
        if let panel = panelController?.currentPanel {
            panel.isOpaque = false
            VoiceHUDWindowLayering.orderFront(panel)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.dismiss()
        }
    }

    func dismiss() {
        panelController?.dismiss(animated: true)
    }
}

private struct VoiceInsertionAnchorView: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.black.opacity(0.72)))
    }
}
