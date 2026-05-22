import SwiftUI

struct AccessibilityPermissionRow: View {
    let status: PermissionDisplayState
    let isHighlighted: Bool
    let onAction: () -> Void

    var body: some View {
        PermissionCard(
            title: "Accessibility",
            reason: "Allows global shortcuts, paste injection, snippet expansion, and window features in the active app.",
            state: status.cardState,
            actionTitle: status == .granted ? "Granted" : "Open",
            isHighlighted: isHighlighted,
            action: onAction
        )
    }
}
