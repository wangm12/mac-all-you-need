import AppKit
import Core
import Foundation
import Platform

/// Drag/drop coordination slice extracted from `ClipboardDockModel`. Owns the
/// teardown sequence for an in-flight dock drag — clears the active dragged
/// item, releases the dock-wide drag surface flag, and bumps the completion
/// tick so child views holding local drag UI state can clear it.
///
/// All three pieces of published state (`activeDraggedItemID`,
/// `isDockDragSurfaceActive`, `dockDragCompletionCount`) live on the facade so
/// SwiftUI observation continues to fire from the same registrar. Direct
/// writes from views (e.g. `model.isDockDragSurfaceActive = false`) continue
/// to flow through the facade's stored properties; this sub-model is invoked
/// for the shared "finish" path that needs to flip all three atomically.
@MainActor
final class DragDropSubModel {
    private unowned let model: ClipboardDockModel

    init(model: ClipboardDockModel) {
        self.model = model
    }

    func finishDockDrag() {
        model.activeDraggedItemID = nil
        model.isDockDragSurfaceActive = false
        model.dockDragCompletionCount += 1
    }
}
