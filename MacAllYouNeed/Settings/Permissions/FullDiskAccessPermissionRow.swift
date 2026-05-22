import SwiftUI

struct FullDiskAccessPermissionRow: View {
    let status: PermissionDisplayState
    let isHighlighted: Bool
    let onAction: () -> Void

    var body: some View {
        PermissionCard(
            title: "Full Disk Access",
            reason: "Allows browser cookie import for authenticated video downloads.",
            state: status.cardState,
            actionTitle: "Open",
            isHighlighted: isHighlighted,
            action: onAction
        )
    }
}
