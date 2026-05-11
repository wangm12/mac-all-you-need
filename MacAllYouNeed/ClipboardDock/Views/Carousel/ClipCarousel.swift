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
    /// Set when a card-reorder drag begins so each slot's drop target can
    /// distinguish a tab-reorder drag from an item-pin drag and live-shift
    /// the carousel as the user moves across neighbors.
    @State private var draggedCardID: String?

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
                            fileThumbnailLoader: model.fileThumbnailLoader,
                            favicons: favicons,
                            draggedCardID: $draggedCardID
                        )
                        .id(item.id)
                        // Cards vanish with a scale+fade when removed (delete /
                        // retention) and slide in from the leading edge when a
                        // new clipboard item arrives. Driven by `withAnimation`
                        // at the call site so we don't propagate implicit
                        // animation to siblings (which previously caused the
                        // selection-border lag).
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .scale(scale: 0.85).combined(with: .opacity)
                            )
                        )
                        // Click semantics (Finder-style):
                        //   • bare click  → replace selection with this card + move anchor here
                        //   • ⌘-click     → toggle this card in/out of selection + move anchor
                        //   • ⇧-click     → extend selection from anchor to this card (additive)
                        //   • ⌥-click     → paste-as-plain (single-shot paste)
                        // Paste is reached via ⌘1-9, ⌘↩, or right-click "Paste to <App>".
                        // Copy is reached via ⌘C or right-click → Copy.
                        //
                        // Single source of truth: a bare onTapGesture reads NSEvent's
                        // modifier flags and dispatches synchronously. Two reasons
                        // we don't use SwiftUI's `TapGesture().modifiers(.command)`
                        // overload here:
                        //   1. Both fire — the bare gesture would still run AND wipe
                        //      the selection before the modifier-specific handler did
                        //      its job, breaking ⌘-click and ⇧-click.
                        //   2. `.onTapGesture(count: 2)` would force a 250ms wait on
                        //      every single-click for double-tap disambiguation.
                        // The modifier read here is synchronous-on-main, so the race
                        // window between mouse-down and closure dispatch is sub-frame.
                        .onTapGesture {
                            handleClick(idx: idx, item: item)
                        }
                        // Double-click = copy this card to the system
                        // clipboard then dismiss the dock. `simultaneousGesture`
                        // (rather than `.onTapGesture(count: 2)`) avoids the
                        // SwiftUI gesture-disambiguation delay that would
                        // otherwise make every single-click wait ~250ms for
                        // a possible second tap. Side effect: the bare
                        // single-click handler ALSO fires on each of the two
                        // taps; that's a no-op (selecting an already-selected
                        // card) so it doesn't matter.
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                Task { @MainActor in
                                    await model.copyToClipboard(itemID: item.id)
                                    CopyHUD.show("Copied")
                                    NotificationCenter.default.post(
                                        name: .dockHideRequested, object: nil
                                    )
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                // Animate the in-memory items reorder so cards slide into
                // their new positions during a live drag (mirrors
                // DockListTabs' tab-reorder animation).
                .animation(.easeInOut(duration: 0.18), value: model.items.map(\.id))
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

    /// Inspect the current modifier state and route the click. Reading
    /// NSEvent.modifierFlags on the main thread inside the tap closure is
    /// safe — the modifier value at click time is already latched into
    /// NSEvent before SwiftUI dispatches the gesture closure.
    private func handleClick(idx: Int, item: DockItem) {
        let mods = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.shift) {
            model.shiftExtendSelection(toItemID: item.id)
            return
        }
        if mods.contains(.command) {
            model.cmdToggleSelection(itemID: item.id)
            return
        }
        if mods.contains(.option) {
            // ⌥-click pastes plain — still go through the existing pipeline
            // so dock-dismiss + 80ms focus-restore are reused.
            onPaste(idx, .option)
            return
        }
        model.selectOnly(itemID: item.id)
    }
}
