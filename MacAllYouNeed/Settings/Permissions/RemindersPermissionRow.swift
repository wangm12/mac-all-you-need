import SwiftUI

struct RemindersPermissionRow: View {
    let status: PermissionDisplayState
    let isHighlighted: Bool
    let onAction: () -> Void

    var body: some View {
        PermissionCard(
            title: "Reminders",
            reason: "Saves spoken tasks from Voice Reminders to Apple Reminders.",
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
