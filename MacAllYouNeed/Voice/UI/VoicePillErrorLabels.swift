import Foundation

/// Maps pipeline / coordinator failure messages to pill labels and blocking alerts.
enum VoicePillErrorLabels {
    static func pillLabel(for message: String) -> String {
        VoiceHUDCopy.pillLabel(for: message)
    }

    static func alertMessage(for message: String) -> String? {
        VoiceHUDCopy.blockingAlert(for: message)?.body
    }

    static func blockingPresentation(for message: String) -> VoiceAlertPresenter.Presentation? {
        guard let alert = VoiceHUDCopy.blockingAlert(for: message) else { return nil }
        let lower = message.lowercased()
        let primary: String?
        let secondary: String?
        if lower.contains("permission") {
            primary = VoiceHUDCopy.Action.openSettings
            secondary = VoiceHUDCopy.Action.dismiss
        } else if lower.contains("microphone") {
            primary = VoiceHUDCopy.Action.retry
            secondary = VoiceHUDCopy.Action.dismiss
        } else if lower.contains("transcribe") || lower.contains("asr") {
            primary = VoiceHUDCopy.Action.retry
            secondary = VoiceHUDCopy.Action.dismiss
        } else {
            primary = VoiceHUDCopy.Action.dismiss
            secondary = nil
        }
        return VoiceAlertPresenter.Presentation(
            title: alert.title,
            body: alert.body,
            kind: .blocking(primary: primary, secondary: secondary),
            symbol: "exclamationmark.triangle"
        )
    }
}
