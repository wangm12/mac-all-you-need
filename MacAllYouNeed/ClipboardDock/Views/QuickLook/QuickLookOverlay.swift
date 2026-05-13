import SwiftUI

struct QuickLookOverlay: View {
    @Bindable var model: ClipboardDockModel

    var body: some View {
        let focusedItem: DockItem? = model.items.indices.contains(model.focusedIndex)
            ? model.items[model.focusedIndex]
            : nil

        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            if let item = focusedItem {
                VStack(spacing: 12) {
                    QuickLookContent(
                        item: item,
                        imageLoader: model.imageLoader,
                        fileLoader: model.fileLoader,
                        xpc: model.xpc
                    )
                    .frame(maxWidth: 800, maxHeight: 480)

                    HStack {
                        Text(item.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.modified, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            }
        }
        .transition(.opacity)
    }
}
