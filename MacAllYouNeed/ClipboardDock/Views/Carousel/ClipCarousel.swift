import AppKit
import SwiftUI

struct ClipCarousel: View {
    @Bindable var model: ClipboardDockModel
    let favicons: FaviconCache
    let registry: ShortcutRegistry
    /// Reports the index plus the modifier state captured at the moment of the
    /// click. Reading NSEvent.modifierFlags later in DockWindowController is a
    /// race — the user may release the modifier before the SwiftUI tap closure
    /// runs, silently downgrading ⌘+click to a destructive paste.
    let onPaste: (Int, EventModifiers) -> Void

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
                        // SwiftUI dispatches the most-specific modifier-matched
                        // gesture, so the order of these stacks does not matter
                        // for correctness — only one fires per click.
                        .onTapGesture { onPaste(idx, []) }
                        .simultaneousGesture(
                            TapGesture().modifiers(.command).onEnded { onPaste(idx, .command) }
                        )
                        .simultaneousGesture(
                            TapGesture().modifiers(.shift).onEnded { onPaste(idx, .shift) }
                        )
                        .simultaneousGesture(
                            TapGesture().modifiers(.option).onEnded { onPaste(idx, .option) }
                        )
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
                let mods: EventModifiers = keyPress.modifiers.contains(.option) ? .option : []
                onPaste(model.focusedIndex, mods)
                return .handled
            default:
                _ = registry
                return .ignored
            }
        }
    }
}
