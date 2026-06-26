import AppKit
import SwiftUI
import UI

/// Blocking alert cards above the voice pill — distinct from caption helpers.
@MainActor
final class VoiceAlertPresenter {
    enum Kind: Equatable {
        case blocking(primary: String?, secondary: String?)
    }

    struct Presentation: Equatable {
        let title: String
        let body: String
        let kind: Kind
        let symbol: String?
    }

    private var panelController: NonActivatingFloatingPanelController<VoiceBlockingAlertView>?
    private var anchorScreen: NSScreen?
    private var pillBottomY: CGFloat = 0
    private var captionStackHeight: CGFloat = 0
    var onPrimaryAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?

    private var pillCenterX: CGFloat?

    func updateAnchor(
        screen: NSScreen?,
        pillBottomY: CGFloat,
        pillCenterX: CGFloat? = nil,
        captionHeight: CGFloat = 0
    ) {
        anchorScreen = screen
        self.pillBottomY = pillBottomY
        self.pillCenterX = pillCenterX
        captionStackHeight = captionHeight
        if panelController?.isPresented == true {
            let size = panelController?.currentPanel?.frame.size ?? CGSize(width: 300, height: 120)
            panelController?.currentPanel?.setFrameOrigin(origin(for: size))
        }
    }

    func show(_ presentation: Presentation) {
        let view = VoiceBlockingAlertView(
            presentation: presentation,
            onPrimary: onPrimaryAction,
            onSecondary: onSecondaryAction
        )
        let size = CGSize(width: 300, height: presentation.body.isEmpty ? 88 : 120)

        if panelController == nil {
            panelController = NonActivatingFloatingPanelController<VoiceBlockingAlertView>(
                styleMask: [.borderless, .nonactivatingPanel],
                level: VoiceHUDWindowLayering.windowLevel + 2,
                collectionBehavior: VoiceHUDWindowLayering.collectionBehavior,
                hasShadow: true,
                backgroundColor: .clear,
                showAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastIn),
                hideAnimationDuration: MAYNMotionBridge.effectiveDuration(.toastOut),
                positioner: { [weak self] panel, panelSize in
                    guard let self else { return }
                    panel.setFrameOrigin(self.origin(for: panelSize))
                }
            )
        }

        if let controller = panelController, controller.isPresented {
            controller.currentPanel?.contentView = NSHostingView(rootView: view)
            controller.updateSize(size)
            if let panel = controller.currentPanel {
                panel.setFrameOrigin(origin(for: size))
                VoiceHUDWindowLayering.orderFront(panel)
            }
        } else {
            panelController?.present(rootView: view, size: size, animated: true)
            if let panel = panelController?.currentPanel {
                panel.isOpaque = false
                VoiceHUDWindowLayering.orderFront(panel)
            }
        }
    }

    func dismiss() {
        panelController?.dismiss(animated: true)
    }

    private func origin(for size: CGSize) -> NSPoint {
        let screen = anchorScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return .zero }
        let frame = screen.visibleFrame
        let obstruction = FloatingBottomObstructionProvider.bottomObstruction(for: frame)
        let pillY = pillBottomY > 0
            ? pillBottomY
            : MiniVoiceHUDLayout.defaultPillBottomY(
                in: frame,
                screenFrame: screen.frame,
                bottomObstruction: obstruction
            )
        let centerX = pillCenterX ?? frame.midX
        return MiniVoiceHUDLayout.alertOrigin(
            pillBottomY: pillY,
            captionHeight: captionStackHeight,
            size: size,
            centerX: centerX
        )
    }
}

struct VoiceBlockingAlertView: View {
    let presentation: VoiceAlertPresenter.Presentation
    let onPrimary: (() -> Void)?
    let onSecondary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: presentation.symbol ?? "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text(presentation.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            if !presentation.body.isEmpty {
                Text(presentation.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case let .blocking(primary, secondary) = presentation.kind {
                HStack(spacing: 8) {
                    if let secondary {
                        MAYNButton(secondary, role: .secondary) { onSecondary?() }
                    }
                    if let primary {
                        MAYNButton(primary, role: .primary) { onPrimary?() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MAYNTheme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}
