import SwiftUI

struct ClipCarousel: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let onPaste: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                        CardSlot(
                            item: item,
                            index: idx,
                            isFocused: idx == model.focusedIndex,
                            imageLoader: model.imageLoader,
                            fileLoader: model.fileLoader,
                            favicons: favicons
                        )
                        .id(item.id)
                        .onTapGesture { onPaste(idx) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: model.focusedIndex) { _, newValue in
                guard model.items.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(model.items[newValue].id, anchor: .center)
                }
            }
        }
    }
}
