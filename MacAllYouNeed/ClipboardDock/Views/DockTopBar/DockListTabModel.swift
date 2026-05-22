import Core
import Foundation

// MARK: - Enums used by the tab strip configuration

enum DockListAddButtonPlacement: Equatable {
    case outsidePill
}

enum DockListTabScrollSizing: Equatable {
    case flexibleViewport
}

enum DockListTabDropTargetPlacement: Equatable {
    case stripContent
}

enum DockListDropTargetLiftStyle: Equatable {
    case liftedTab
}

enum DockListDropSurfaceActivation: Equatable {
    case windowDragOrActiveDrag
}

enum DockListTabReorderPlacement: Equatable {
    case before
    case after
}

// MARK: - Reorder target

struct DockListTabReorderTarget: Equatable {
    let targetID: RecordID
    let placement: DockListTabReorderPlacement

    var selector: DockListSelector {
        .pinboard(targetID)
    }
}

// MARK: - Drop policy

enum DockListItemTabDropPolicy {
    static func acceptsPerTabDrop(draggedTabID: RecordID?) -> Bool {
        draggedTabID == nil
    }
}

// MARK: - Presentation constants

enum DockListTabsPresentation {
    static let historyLabel = "Clipboard History"
    static let snippetsLabel = "Snippets"
    static let addButtonPlacement: DockListAddButtonPlacement = .outsidePill
    static let usesNSItemProviderCompatibleDropTarget = true
    static let inactiveTabsKeepTransparentDropSurface = true
    static let tabDropSurfaceAvoidsNestedButton = true
    static let scrollSizing: DockListTabScrollSizing = .flexibleViewport
    static let usesSingleStripDropCoordinator = true
    static let usesAppKitDropBackstop = true
    static let usesPerItemTabDropTarget = true
    static let dropSurfaceActivation: DockListDropSurfaceActivation = .windowDragOrActiveDrag
    static let appKitDropSurfaceFillsTabPill = true
    static let dropTargetPlacement: DockListTabDropTargetPlacement = .stripContent
    static let dropTargetLiftStyle: DockListDropTargetLiftStyle = .liftedTab
    static let dropCoordinateSpace = "DockListTabsDropCoordinateSpace"

    static func pillTabLabels(pinboardNames: [String]) -> [String] {
        [historyLabel, snippetsLabel] + pinboardNames
    }
}

// MARK: - Drop frame model

struct DockListTabDropFrame: Equatable {
    let selector: DockListSelector
    let rect: CGRect
}

extension DockListTabDropFrame {
    var isPinboard: Bool {
        if case .pinboard = selector { return true }
        return false
    }

    var acceptsItemDrop: Bool {
        selector.acceptsItemDrop
    }

    var hitRect: CGRect {
        rect.insetBy(dx: -3, dy: -4)
    }

    func horizontalDistance(to x: CGFloat) -> CGFloat {
        if x < rect.minX { return rect.minX - x }
        if x > rect.maxX { return x - rect.maxX }
        return 0
    }
}

extension [DockListTabDropFrame] {
    var verticalRange: ClosedRange<CGFloat>? {
        guard let first else { return nil }
        var minY = first.rect.minY
        var maxY = first.rect.maxY
        for frame in dropFirst() {
            minY = Swift.min(minY, frame.rect.minY)
            maxY = Swift.max(maxY, frame.rect.maxY)
        }
        return minY ... maxY
    }
}

extension DockListSelector {
    var acceptsItemDrop: Bool {
        switch self {
        case .snippets, .pinboard:
            return true
        case .history:
            return false
        }
    }
}

// MARK: - Drop surface activation

enum DockListDropSurfaceState {
    static func isActive(
        draggedTabID: RecordID?,
        activeDraggedItemID: DockItem.ID?,
        windowDragIsActive: Bool
    ) -> Bool {
        draggedTabID != nil || activeDraggedItemID != nil || windowDragIsActive
    }
}
