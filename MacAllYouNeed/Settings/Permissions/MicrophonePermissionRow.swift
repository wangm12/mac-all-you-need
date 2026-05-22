import SwiftUI

struct MicrophonePermissionRow: View {
    let status: PermissionDisplayState
    let isHighlighted: Bool
    let onAction: () -> Void

    var body: some View {
        PermissionCard(
            title: "Microphone",
            reason: "Allows voice dictation and the voice setup test to capture local audio.",
            state: status.cardState,
            actionTitle: actionTitle,
            isHighlighted: isHighlighted,
            action: onAction
        )
    }

    private var actionTitle: String {
        switch status {
        case .granted:
            "Granted"
        case .denied:
            "Open"
        default:
            "Request"
        }
    }
}
