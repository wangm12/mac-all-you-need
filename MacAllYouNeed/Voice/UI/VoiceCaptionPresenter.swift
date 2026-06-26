import AppKit
import Core
import SwiftUI
import UI

/// Caption-style helper above the voice pill — compact blur chip for legibility on busy desktops.
@MainActor
final class VoiceCaptionPresenter {
    private var panelController: NonActivatingFloatingPanelController<VoiceCaptionView>?
    private var dismissTask: Task<Void, Never>?
    private var anchorScreen: NSScreen?
    private var pillBottomY: CGFloat = 0
    private(set) var currentPriority: VoiceHUDCopy.Priority?
    private(set) var currentMessage: String?

    var presentedStackHeight: CGFloat {
        guard panelController?.isPresented == true, let message = currentMessage else { return 0 }
        return Self.size(for: message).height
    }

    private var pillCenterX: CGFloat?

    func updateAnchor(screen: NSScreen?, pillBottomY: CGFloat, pillCenterX: CGFloat? = nil) {
        anchorScreen = screen
        self.pillBottomY = pillBottomY
        self.pillCenterX = pillCenterX
        if panelController?.isPresented == true, let message = currentMessage {
            reposition(message: message)
        }
    }

    /// Shows a caption when `priority` is at least as important as the current caption.
    func show(
        _ message: String,
        priority: VoiceHUDCopy.Priority,
        duration: TimeInterval?
    ) {
        if let currentPriority, priority > currentPriority { return }

        dismissTask?.cancel()
        currentPriority = priority
        currentMessage = message

        let view = VoiceCaptionView(message: message)
        let size = Self.size(for: message)

        if panelController == nil {
            panelController = NonActivatingFloatingPanelController<VoiceCaptionView>(
                styleMask: [.borderless, .nonactivatingPanel],
                level: VoiceHUDWindowLayering.windowLevel + 1,
                collectionBehavior: VoiceHUDWindowLayering.collectionBehavior,
                hasShadow: false,
                backgroundColor: .clear,
                showAnimationDuration: 0,
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
            if let panel = panelController?.currentPanel {
                panel.alphaValue = 1
                panel.setFrameOrigin(origin(for: size))
                VoiceHUDWindowLayering.configureGlassPanel(panel, acceptsMouseEvents: false)
                VoiceHUDWindowLayering.orderFront(panel)
            }
        } else {
            panelController?.present(rootView: view, size: size, animated: false)
            if let panel = panelController?.currentPanel {
                VoiceHUDWindowLayering.configureGlassPanel(panel, acceptsMouseEvents: false)
                VoiceHUDWindowLayering.orderFront(panel)
            }
        }

        if let duration {
            dismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        currentPriority = nil
        currentMessage = nil
        panelController?.dismiss(animated: false)
    }

    private func reposition(message: String) {
        let size = Self.size(for: message)
        panelController?.updateSize(size)
        panelController?.currentPanel?.setFrameOrigin(origin(for: size))
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
        return MiniVoiceHUDLayout.captionOrigin(
            pillBottomY: pillY,
            size: size,
            centerX: centerX
        )
    }

    private static func size(for message: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: MiniVoiceHUDLayout.captionFontSize, weight: .medium)
        let textWidth = (message as NSString).size(withAttributes: [.font: font]).width
        let width = min(320, textWidth + MiniVoiceHUDLayout.captionHorizontalPadding * 2)
        return CGSize(width: max(120, width), height: MiniVoiceHUDLayout.captionShellHeight)
    }
}

struct VoiceCaptionView: View {
    let message: String
    @AppStorage(VoiceHUDAppearanceStore.storageKey, store: AppGroupSettings.defaults)
    private var appearanceRaw = VoiceHUDAppearance.glass.rawValue

    private var usesGraphiteChrome: Bool {
        (VoiceHUDAppearance(rawValue: appearanceRaw) ?? .glass) == .graphite
    }

    var body: some View {
        Text(message)
            .font(.system(size: MiniVoiceHUDLayout.captionFontSize, weight: .medium))
            .foregroundStyle(
                usesGraphiteChrome
                    ? MiniVoiceHUDPalette.pillText.opacity(0.92)
                    : Color.primary.opacity(0.88)
            )
            .lineLimit(1)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MiniVoiceHUDLayout.captionHorizontalPadding)
            .padding(.vertical, MiniVoiceHUDLayout.captionVerticalPadding)
            .voiceHubCaptionChrome(isGraphite: usesGraphiteChrome)
            .compositingGroup()
            .clipShape(
                RoundedRectangle(cornerRadius: MiniVoiceHUDLayout.captionCornerRadius, style: .continuous)
            )
    }
}
