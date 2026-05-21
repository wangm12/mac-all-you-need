import AppKit
import Core
import Platform
import SwiftUI
import UI

enum KeyboardShortcutFloatingOverlayPresentation {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let acceptsMouseEvents = true

    static func origin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        )
    }
}

@MainActor
final class KeyboardShortcutFloatingOverlayController {
    private var panelController: NonActivatingFloatingPanelController<KeyboardShortcutVisualizer>?

    func update(
        state: KeyboardShortcutVisualizerState,
        candidate: HotkeyDescriptor? = nil,
        issueMessage: String? = nil,
        onReset: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        guard state.isRecording else {
            dismiss()
            return
        }
        show(
            state,
            candidate: candidate,
            issueMessage: issueMessage,
            onReset: onReset,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    func owns(window: NSWindow?) -> Bool {
        guard let window else { return false }
        return panelController?.currentPanel === window
    }

    func dismiss(immediate: Bool = false) {
        guard panelController?.isPresented == true else { return }
        panelController?.dismiss(animated: !immediate && MAYNMotionBridge.effectiveDuration(.toastOut) > 0)
    }

    private func show(
        _ state: KeyboardShortcutVisualizerState,
        candidate: HotkeyDescriptor?,
        issueMessage: String?,
        onReset: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let rootView = KeyboardShortcutVisualizer(
            state: state,
            candidate: candidate,
            issueMessage: issueMessage,
            onReset: onReset,
            onConfirm: onConfirm,
            onCancel: onCancel
        )

        if let controller = panelController, controller.isPresented {
            controller.update(rootView: rootView)
            return
        }

        let controller = panelController ?? makeController()
        panelController = controller

        // Compute size via a temporary hosting view so the panel is given the
        // correct dimensions from the first frame.
        let sizer = NSHostingView(rootView: rootView)
        sizer.layoutSubtreeIfNeeded()
        var size = sizer.fittingSize
        size.width = max(size.width, KeyboardShortcutVisualizerPresentation.width)

        let animated = MAYNMotionBridge.effectiveDuration(.toastIn) > 0
        controller.present(rootView: rootView, size: size, animated: animated)
        // Mirror FloatingHUDWindowLayering.configure settings not exposed by
        // NonActivatingFloatingPanelController: keep the overlay visible even
        // when the app deactivates, and accept mouse events.
        controller.currentPanel?.hidesOnDeactivate = false
        controller.currentPanel?.ignoresMouseEvents = false
    }

    private func makeController() -> NonActivatingFloatingPanelController<KeyboardShortcutVisualizer> {
        NonActivatingFloatingPanelController(
            styleMask: KeyboardShortcutFloatingOverlayPresentation.styleMask,
            level: FloatingHUDWindowLayering.windowLevel,
            collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
            hasShadow: true,
            backgroundColor: .clear,
            showAnimationDuration: MAYNMotionDuration.toastIn,
            hideAnimationDuration: MAYNMotionDuration.toastOut,
            positioner: { panel, panelSize in
                let mouse = NSEvent.mouseLocation
                let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first
                guard let visibleFrame = screen?.visibleFrame else { return }
                panel.setFrameOrigin(
                    KeyboardShortcutFloatingOverlayPresentation.origin(
                        panelSize: panelSize,
                        visibleFrame: visibleFrame
                    )
                )
            }
        )
    }
}
