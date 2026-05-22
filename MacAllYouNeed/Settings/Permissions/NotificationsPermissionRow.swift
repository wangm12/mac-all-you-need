import SwiftUI

struct NotificationsPermissionRow: View {
    let status: PermissionDisplayState
    let isHighlighted: Bool
    let onAction: () -> Void

    var body: some View {
        PermissionCard(
            title: "Notifications",
            reason: "Shows download completion and failure alerts.",
            state: status.cardState,
            actionTitle: PermissionActionPresentation.notificationActionTitle(for: status),
            isHighlighted: isHighlighted,
            action: onAction
        )
    }
}
