import AppKit
import SwiftUI

struct ClipCarousel: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    let onPaste: (Int, Bool) -> Void

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
                        .onTapGesture {
                            onPaste(idx, false)
                        }
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
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            let raw = keyPress.key.character
            switch raw {
            case Character(UnicodeScalar(NSLeftArrowFunctionKey)!):
                model.focusBackward()
                return .handled
            case Character(UnicodeScalar(NSRightArrowFunctionKey)!):
                model.focusForward()
                return .handled
            case "\r":
                let plainText = keyPress.modifiers.contains(.option)
                onPaste(model.focusedIndex, plainText)
                return .handled
            default:
                _ = registry
                return .ignored
            }
        }
    }
}
