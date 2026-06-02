import SwiftUI

/// Collapsible advanced settings block (DockDoor progressive-disclosure pattern).
struct DockAdvancedSettingsDisclosure<Content: View>: View {
    @State private var isExpanded = false
    @ViewBuilder let content: Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}
