import AppKit
import Core
import SwiftUI

// MARK: - SwiftUI strip-level drop delegate

struct DockListStripDropDelegate: DropDelegate {
    let tabFrames: [DockListTabDropFrame]
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty &&
            resolvedTarget(for: info) != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard updateDropTarget(for: info) != nil else { return nil }
        return DropProposal(operation: draggedTabID == nil ? .copy : .move)
    }

    func dropEntered(info: DropInfo) {
        _ = updateDropTarget(for: info)
    }

    func dropExited(info _: DropInfo) {
        if draggedTabID == nil {
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
                dropTargetSelector = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers)
        guard let target = resolvedTarget(for: info), !providers.isEmpty else {
            dropTargetSelector = nil
            draggedTabID = nil
            return false
        }
        if let draggedID = draggedTabID,
           let reorderTarget = resolvedReorderTarget(for: info),
           draggedID != reorderTarget.targetID
        {
            liveReorderTab(draggedID, reorderTarget)
        }

        DockDragPayloadLoader.strings(from: providers) { strings in
            let isTabReorder = strings.contains { DockTabDrag.decode($0) != nil }
            let accepted = handleDrop(strings, target)
            if accepted, !isTabReorder {
                runDropConfirmation(target)
            }
            dropTargetSelector = nil
        }
        return true
    }

    private func updateDropTarget(for info: DropInfo) -> DockListSelector? {
        let target = resolvedTarget(for: info)

        if let draggedID = draggedTabID,
           let reorderTarget = resolvedReorderTarget(for: info),
           draggedID != reorderTarget.targetID
        {
            liveReorderTab(draggedID, reorderTarget)
            dropTargetSelector = nil
            return target
        }

        guard draggedTabID == nil else { return target }
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
            dropTargetSelector = target
        }
        return target
    }

    private func resolvedTarget(for info: DropInfo) -> DockListSelector? {
        if draggedTabID != nil {
            return resolvedReorderTarget(for: info)?.selector
        }
        return DockListTabDropResolver.targetSelector(
            at: info.location,
            in: tabFrames,
            requiresItemDropTarget: true
        )
    }

    private func resolvedReorderTarget(for info: DropInfo) -> DockListTabReorderTarget? {
        DockListTabDropResolver.reorderTarget(at: info.location, in: tabFrames)
    }
}

// MARK: - Per-item tab drop modifier + delegate

struct DockListItemTabDropTarget: ViewModifier {
    let selector: DockListSelector
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if selector.acceptsItemDrop {
            content.onDrop(
                of: DockDragPayloadTypes.acceptedTypeIdentifiers,
                delegate: DockListItemTabDropDelegate(
                    selector: selector,
                    dropTargetSelector: $dropTargetSelector,
                    draggedTabID: $draggedTabID,
                    reduceMotion: reduceMotion,
                    liveReorderTab: liveReorderTab,
                    handleDrop: handleDrop,
                    runDropConfirmation: runDropConfirmation
                )
            )
        } else {
            content
        }
    }
}

private struct DockListItemTabDropDelegate: DropDelegate {
    let selector: DockListSelector
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) &&
            !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) else {
            return nil
        }
        guard !info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers).isEmpty else {
            return nil
        }
        updateDropTarget()
        return DropProposal(operation: draggedTabID == nil ? .copy : .move)
    }

    func dropEntered(info _: DropInfo) {
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) else { return }
        updateDropTarget()
    }

    func dropExited(info _: DropInfo) {
        if draggedTabID == nil {
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
                dropTargetSelector = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: DockDragPayloadTypes.acceptedTypeIdentifiers)
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID),
              !providers.isEmpty
        else {
            dropTargetSelector = nil
            draggedTabID = nil
            return false
        }

        DockDragPayloadLoader.strings(from: providers) { strings in
            let isTabReorder = strings.contains { DockTabDrag.decode($0) != nil }
            let accepted = handleDrop(strings, selector)
            if accepted, !isTabReorder {
                runDropConfirmation(selector)
            }
            dropTargetSelector = nil
            if !accepted {
                draggedTabID = nil
            }
        }
        return true
    }

    private func updateDropTarget() {
        guard DockListItemTabDropPolicy.acceptsPerTabDrop(draggedTabID: draggedTabID) else { return }
        withAnimation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion)) {
            dropTargetSelector = selector
        }
    }
}

// MARK: - AppKit drop surface backstop

struct DockListStripAppKitDropSurface: NSViewRepresentable {
    let tabFrames: [DockListTabDropFrame]
    @Binding var dropTargetSelector: DockListSelector?
    @Binding var draggedTabID: RecordID?
    let reduceMotion: Bool
    let liveReorderTab: (RecordID, DockListTabReorderTarget) -> Void
    let handleDrop: ([String], DockListSelector) -> Bool
    let runDropConfirmation: (DockListSelector) -> Void

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
        var parent: DockListStripAppKitDropSurface

        init(_ parent: DockListStripAppKitDropSurface) {
            self.parent = parent
        }

        func updateDropTarget(for sender: NSDraggingInfo, location: CGPoint) -> NSDragOperation {
            guard hasSupportedPayload(sender),
                  let target = resolvedTarget(at: location)
            else {
                clearDropTargetIfNeeded()
                return []
            }

            if let draggedID = parent.draggedTabID,
               let reorderTarget = resolvedReorderTarget(at: location),
               draggedID != reorderTarget.targetID
            {
                parent.liveReorderTab(draggedID, reorderTarget)
                parent.dropTargetSelector = nil
                return .move
            }

            guard parent.draggedTabID == nil else { return .move }
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: parent.reduceMotion)) {
                parent.dropTargetSelector = target
            }
            return .copy
        }

        func performDrop(for sender: NSDraggingInfo, location: CGPoint) -> Bool {
            guard hasSupportedPayload(sender),
                  let target = resolvedTarget(at: location)
            else {
                parent.dropTargetSelector = nil
                parent.draggedTabID = nil
                return false
            }
            if let draggedID = parent.draggedTabID,
               let reorderTarget = resolvedReorderTarget(at: location),
               draggedID != reorderTarget.targetID
            {
                parent.liveReorderTab(draggedID, reorderTarget)
            }

            let strings = pasteboardStrings(from: sender.draggingPasteboard)
            let isTabReorder = strings.contains { DockTabDrag.decode($0) != nil }
            let accepted = parent.handleDrop(strings, target)
            if accepted, !isTabReorder {
                parent.runDropConfirmation(target)
            }
            parent.dropTargetSelector = nil
            if !accepted {
                parent.draggedTabID = nil
            }
            return accepted
        }

        func clearDropTargetIfNeeded() {
            guard parent.draggedTabID == nil else { return }
            withAnimation(MAYNMotion.tabAnimation(reduceMotion: parent.reduceMotion)) {
                parent.dropTargetSelector = nil
            }
        }

        private func hasSupportedPayload(_ sender: NSDraggingInfo) -> Bool {
            sender.draggingPasteboard.availableType(
                from: DockDragPayloadTypes.acceptedPasteboardTypes
            ) != nil
        }

        private func resolvedTarget(at location: CGPoint) -> DockListSelector? {
            if parent.draggedTabID != nil {
                return resolvedReorderTarget(at: location)?.selector
            }
            return DockListTabDropResolver.targetSelector(
                at: location,
                in: parent.tabFrames,
                requiresItemDropTarget: true
            )
        }

        private func resolvedReorderTarget(at location: CGPoint) -> DockListTabReorderTarget? {
            DockListTabDropResolver.reorderTarget(
                at: location,
                in: parent.tabFrames
            )
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
            coordinator?.clearDropTargetIfNeeded()
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
