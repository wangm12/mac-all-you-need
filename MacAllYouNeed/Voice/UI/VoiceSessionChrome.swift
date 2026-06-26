import AppKit
import Foundation

/// Composition root for the voice interaction surface:
/// centered pill, caption helpers, and blocking alerts.
@MainActor
final class VoiceSessionChrome {
    let pill = MiniVoiceHUD()
    let captions = VoiceCaptionPresenter()
    let alerts = VoiceAlertPresenter()
    let insertionAnchor = VoiceInsertionAnchorPresenter()
    private var obstructionObserver: NSObjectProtocol?

    init() {
        obstructionObserver = NotificationCenter.default.addObserver(
            forName: FloatingBottomObstructionProvider.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAlertAnchor()
            }
        }
    }

    deinit {
        if let obstructionObserver {
            NotificationCenter.default.removeObserver(obstructionObserver)
        }
    }

    func syncAlertAnchor() {
        let screen = pill.currentTargetScreen
        let bottomY = pill.currentPillBottomY
        let centerX = pill.currentPillCenterX
        let captionHeight = captions.presentedStackHeight
        captions.updateAnchor(screen: screen, pillBottomY: bottomY, pillCenterX: centerX)
        alerts.updateAnchor(
            screen: screen,
            pillBottomY: bottomY,
            pillCenterX: centerX,
            captionHeight: captionHeight
        )
    }

    func dismissAll() {
        captions.dismiss()
        alerts.dismiss()
        pill.dismiss()
    }
}
