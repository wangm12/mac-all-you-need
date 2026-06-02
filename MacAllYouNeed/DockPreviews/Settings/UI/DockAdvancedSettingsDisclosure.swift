import SwiftUI

/// Collapsible advanced settings block. Content is built only while expanded to keep expand snappy.
struct DockAdvancedSettingsDisclosure<Content: View>: View {
    @State private var isExpanded = false
    @ViewBuilder private let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("Advanced")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(.top, 10)
            }
        }
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isExpanded)
    }
}
