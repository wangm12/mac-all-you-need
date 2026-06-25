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

    func syncAlertAnchor() {
        let screen = pill.currentTargetScreen
        let bottomY = pill.currentPillBottomY
        let centerX = pill.currentPillCenterX
        captions.updateAnchor(screen: screen, pillBottomY: bottomY, pillCenterX: centerX)
        alerts.updateAnchor(screen: screen, pillBottomY: bottomY, pillCenterX: centerX)
    }

    func dismissAll() {
        captions.dismiss()
        alerts.dismiss()
        pill.dismiss()
    }
}
