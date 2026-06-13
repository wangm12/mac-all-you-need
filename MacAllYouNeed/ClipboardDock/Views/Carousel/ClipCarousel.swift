import AppKit
import Core
import Platform
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
    @State private var nativeDraggedCardID: String?
    @State private var cardDropFrames: [DockCardDropFrame] = []
    @State private var cardDropTarget: DockCardReorderTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Context-aware ranked items for display. Delegates to model.displayItems
    /// which applies ranking only when browsing history without active search.
    private var displayItems: [DockItem] { model.displayItems }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { idx, item in
                            CardSlot(
                                item: item,
                                index: idx,
                                isFocused: idx == model.focusedIndex,
                                imageLoader: model.imageLoader,
                                fileLoader: model.fileLoader,
                                fileThumbnailLoader: model.fileThumbnailLoader,
                                favicons: favicons,
                                draggedCardID: $draggedCardID,
                                nativeDraggedCardID: $nativeDraggedCardID,
                                onLocalReorderDragChanged: handleLocalCardDragChanged(itemID:localLocation:),
                                onLocalReorderDragEnded: handleLocalCardDragEnded(itemID:localLocation:)
                            )
                            .background(DockCardDropFrameReporter(itemID: item.id))
                            .id(item.id)
                            // Cards vanish with a blur+scale+fade when removed (delete /
                            // retention) and slide in from the leading edge when a
                            // new clipboard item arrives. Driven by `withAnimation`
                            // at the call site so we don't propagate implicit
                            // animation to siblings (which previously caused the
                            // selection-border lag).
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .cardRemoval(reduceMotion: reduceMotion)
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
                                    // Option+double-click → copy Smart Text result when enabled
                                    let optionHeld = NSEvent.modifierFlags.contains(.option)
                                    let smartValue = item.smartCopyValue
                                    if SmartTextSettings.optionDoubleClickEnabled(), optionHeld, let value = smartValue {
                                        let pb = NSPasteboard.general
                                        pb.clearContents()
                                        pb.setString(value, forType: .string)
                                        pb.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
                                        CopyHUD.show("Copied Smart Text")
                                        return
                                    }
                                    // Normal double-click → copy entire item + dismiss
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

                        if model.isActiveListReorderable {
                            CardTrailingDropTarget(draggedCardID: $draggedCardID)
                                .frame(width: DockCardReorderPresentation.trailingDropTargetWidth, height: 240)
                        }
                    }
                    .padding(.horizontal, 16)
                    // Animate the in-memory items reorder so cards slide into
                    // their new positions during a live drag (mirrors
                    // DockListTabs' tab-reorder animation).
                    .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: model.items.map(\.id))
                }
                .onChange(of: model.focusedIndex) { _, newValue in
                    guard displayItems.indices.contains(newValue) else { return }
                    withAnimation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion)) {
                        proxy.scrollTo(displayItems[newValue].id, anchor: .center)
                    }
                }
            }

            if cardDropSurfaceIsActive {
                DockCardAppKitDropSurface(
                    cardFrames: cardDropFrames,
                    dropTarget: $cardDropTarget,
                    draggedCardID: $draggedCardID,
                    reduceMotion: reduceMotion,
                    handleDrop: handleAppKitCardDrop(strings:target:)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .zIndex(40)
            }

            if let indicatorFrame {
                Rectangle()
                    .fill(MAYNTheme.focusRing)
                    .frame(width: 4, height: max(24, indicatorFrame.height - 8))
                    .position(x: indicatorFrame.x, y: indicatorFrame.y)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(50)
            }
        }
        .coordinateSpace(name: DockCardReorderPresentation.dropCoordinateSpace)
        .onPreferenceChange(DockCardDropFramePreferenceKey.self) { frames in
            cardDropFrames = frames
        }
        .onChange(of: model.activeDraggedItemID) { _, _ in
            clearCardDragStateIfNeeded()
        }
        .onChange(of: model.isDockDragSurfaceActive) { _, _ in
            clearCardDragStateIfNeeded()
        }
        .onChange(of: model.dockDragCompletionCount) { _, _ in
            clearCardDragState()
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

    private var cardDropSurfaceIsActive: Bool {
        model.isActiveListReorderable && nativeDraggedCardID != nil
    }

    private var indicatorFrame: (x: CGFloat, y: CGFloat, height: CGFloat)? {
        guard let cardDropTarget,
              let frame = cardDropFrames.first(where: { $0.itemID == cardDropTarget.itemID })?.rect
        else { return nil }

        let x: CGFloat
        switch cardDropTarget.placement {
        case .before:
            x = frame.minX
        case .after:
            x = frame.maxX
        }

        return (x: x, y: frame.midY, height: frame.height)
    }

    private func handleAppKitCardDrop(strings: [String], target: DockCardReorderTarget) -> Bool {
        guard let raw = strings.first(where: { DockItemDrag.decode($0) != nil }),
              let sourceID = DockItemDrag.decode(raw),
              sourceID != target.itemID
        else {
            clearCardDragState()
            return false
        }

        Task { @MainActor in
            await model.reorderCardInActivePinboard(
                movingID: sourceID,
                targetID: target.itemID,
                placement: target.placement
            )
            clearCardDragState()
        }
        return true
    }

    private func clearCardDragState() {
        cardDropTarget = nil
        draggedCardID = nil
        nativeDraggedCardID = nil
        model.activeDraggedItemID = nil
        model.isDockDragSurfaceActive = false
    }

    private func clearCardDragStateIfNeeded() {
        guard DockCardDragStatePolicy.shouldClearLocalDrag(
            draggedCardID: draggedCardID,
            nativeDraggedCardID: nativeDraggedCardID,
            activeDraggedItemID: model.activeDraggedItemID,
            isDockDragSurfaceActive: model.isDockDragSurfaceActive
        ) else { return }
        cardDropTarget = nil
        draggedCardID = nil
        nativeDraggedCardID = nil
    }

    private func handleLocalCardDragChanged(itemID: String, localLocation: CGPoint) {
        guard model.isActiveListReorderable,
              let location = dropLocation(for: itemID, localLocation: localLocation)
        else {
            cardDropTarget = nil
            return
        }

        model.activeDraggedItemID = itemID
        model.isDockDragSurfaceActive = true
        let target = DockCardDropResolver.reorderTarget(
            at: location,
            in: cardDropFrames
        )
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
            if target?.itemID == itemID {
                cardDropTarget = nil
            } else {
                cardDropTarget = target
            }
        }
    }

    private func handleLocalCardDragEnded(itemID: String, localLocation: CGPoint) {
        guard model.isActiveListReorderable,
              let location = dropLocation(for: itemID, localLocation: localLocation),
              let target = DockCardDropResolver.reorderTarget(at: location, in: cardDropFrames),
              target.itemID != itemID
        else {
            clearCardDragState()
            return
        }

        Task { @MainActor in
            await model.reorderCardInActivePinboard(
                movingID: itemID,
                targetID: target.itemID,
                placement: target.placement
            )
            clearCardDragState()
        }
    }

    private func dropLocation(for itemID: String, localLocation: CGPoint) -> CGPoint? {
        guard let sourceFrame = cardDropFrames.first(where: { $0.itemID == itemID })?.rect else {
            return nil
        }
        return CGPoint(
            x: sourceFrame.minX + localLocation.x,
            y: sourceFrame.minY + localLocation.y
        )
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

private struct DockCardDropFrameReporter: View {
    let itemID: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DockCardDropFramePreferenceKey.self,
                value: [
                    DockCardDropFrame(
                        itemID: itemID,
                        rect: proxy.frame(in: .named(DockCardReorderPresentation.dropCoordinateSpace))
                    )
                ]
            )
        }
    }
}

private struct DockCardDropFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DockCardDropFrame] = []

    static func reduce(value: inout [DockCardDropFrame], nextValue: () -> [DockCardDropFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct DockCardAppKitDropSurface: NSViewRepresentable {
    let cardFrames: [DockCardDropFrame]
    @Binding var dropTarget: DockCardReorderTarget?
    @Binding var draggedCardID: String?
    let reduceMotion: Bool
    let handleDrop: ([String], DockCardReorderTarget) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.coordinator = context.coordinator
        view.registerForDraggedTypes(DockDragPayloadTypes.acceptedPasteboardTypes)
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        nsView.registerForDraggedTypes(DockDragPayloadTypes.acceptedPasteboardTypes)
    }

    final class Coordinator {
        var parent: DockCardAppKitDropSurface

        init(_ parent: DockCardAppKitDropSurface) {
            self.parent = parent
        }

        func updateDropTarget(for sender: NSDraggingInfo, location: CGPoint) -> NSDragOperation {
            guard hasSupportedPayload(sender),
                  let target = resolvedTarget(at: location)
            else {
                clearDropTarget()
                return []
            }

            withAnimation(MAYNMotion.tabAnimation(reduceMotion: parent.reduceMotion)) {
                parent.dropTarget = target
            }
            return .move
        }

        func performDrop(for sender: NSDraggingInfo, location: CGPoint) -> Bool {
            guard hasSupportedPayload(sender),
                  let target = resolvedTarget(at: location)
            else {
                clearDropTarget()
                parent.draggedCardID = nil
                return false
            }

            let strings = pasteboardStrings(from: sender.draggingPasteboard)
            let accepted = parent.handleDrop(strings, target)
            if !accepted {
                clearDropTarget()
                parent.draggedCardID = nil
            }
            return accepted
        }

        func clearDropTarget() {
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: parent.reduceMotion)) {
                parent.dropTarget = nil
            }
        }

        private func hasSupportedPayload(_ sender: NSDraggingInfo) -> Bool {
            sender.draggingPasteboard.availableType(
                from: DockDragPayloadTypes.acceptedPasteboardTypes
            ) != nil
        }

        private func resolvedTarget(at location: CGPoint) -> DockCardReorderTarget? {
            guard let target = DockCardDropResolver.reorderTarget(
                at: location,
                in: parent.cardFrames
            ) else { return nil }
            guard target.itemID != parent.draggedCardID else { return nil }
            return target
        }

        private func pasteboardStrings(from pasteboard: NSPasteboard) -> [String] {
            var seen = Set<String>()
            return DockDragPayloadTypes.acceptedPasteboardTypes.compactMap { type in
                pasteboard.string(forType: type)
            }.filter { seen.insert($0).inserted }
        }
    }

    final class DropView: NSView {
        var coordinator: Coordinator?

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            coordinator?.updateDropTarget(for: sender, location: localLocation(for: sender)) ?? []
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            coordinator?.updateDropTarget(for: sender, location: localLocation(for: sender)) ?? []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            _ = sender
            coordinator?.clearDropTarget()
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            coordinator?.updateDropTarget(for: sender, location: localLocation(for: sender)) != []
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            coordinator?.performDrop(for: sender, location: localLocation(for: sender)) ?? false
        }

        private func localLocation(for sender: NSDraggingInfo) -> CGPoint {
            convert(sender.draggingLocation, from: nil)
        }
    }
}

private struct CardTrailingDropTarget: View {
    @Binding var draggedCardID: String?
    @Environment(ClipboardDockModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .contentShape(Rectangle())

            if isTargeted, draggedCardID != nil {
                Capsule()
                    .fill(MAYNTheme.focusRing)
                    .frame(width: 4, height: 212)
                    .transition(.opacity)
            }
        }
        .onDrop(
            of: DockDragPayloadTypes.acceptedTypeIdentifiers,
            delegate: CardAppendDropDelegate(
                draggedCardID: $draggedCardID,
                isTargeted: $isTargeted,
                action: handleAppendDrop(strings:)
            )
        )
    }

    private func handleAppendDrop(strings: [String]) -> Bool {
        guard let raw = strings.first(where: { DockItemDrag.decode($0) != nil }),
              let sourceID = DockItemDrag.decode(raw)
        else {
            draggedCardID = nil
            model.activeDraggedItemID = nil
            model.isDockDragSurfaceActive = false
            return false
        }

        Task { @MainActor in
            await model.appendCardInActivePinboard(movingID: sourceID)
            draggedCardID = nil
            model.activeDraggedItemID = nil
            model.isDockDragSurfaceActive = false
        }
        return true
    }
}

private struct CardAppendDropDelegate: DropDelegate {
    @Binding var draggedCardID: String?
    @Binding var isTargeted: Bool
    let action: ([String]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        draggedCardID != nil &&
            !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info _: DropInfo) {
        isTargeted = draggedCardID != nil
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers)
        guard draggedCardID != nil, !providers.isEmpty else {
            isTargeted = false
            return false
        }

        DockDragPayloadLoader.strings(from: providers) { strings in
            _ = action(strings)
            isTargeted = false
        }
        return true
    }
}

// MARK: - Card removal transition

/// Animatable modifier that drives three sequential removal phases from a
/// single [0,1] progress value:
///   Phase 1 (t 0→0.2):  blur ramps from 0 → 10
///   Phase 2 (t 0.2→0.6): opacity ramps from 1 → 0 and scale 1 → 0.85
///   Phase 3 (t 0.6→1.0): scale ramps from 0.85 → 0 (collapse to nothing)
/// When reduceMotion is true the card fades without spatial motion.
private struct CardRemovalModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let blur: CGFloat = reduceMotion ? 0 : min(progress / 0.2, 1) * 10
        let opacity: Double = progress < 0.2 ? 1 : Double(1 - min((progress - 0.2) / 0.4, 1))
        let scale: CGFloat = {
            if reduceMotion { return 1 }
            if progress < 0.2 { return 1 }
            let p2 = min((progress - 0.2) / 0.4, 1)
            let p3 = progress < 0.6 ? 0 : min((progress - 0.6) / 0.4, 1)
            return 1 - p2 * 0.15 - p3 * 0.85
        }()
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

private extension AnyTransition {
    static func cardRemoval(reduceMotion: Bool) -> AnyTransition {
        .modifier(
            active: CardRemovalModifier(progress: 1, reduceMotion: reduceMotion),
            identity: CardRemovalModifier(progress: 0, reduceMotion: reduceMotion)
        )
    }
}
