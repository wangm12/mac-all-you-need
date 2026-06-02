import AppKit
import CoreGraphics
import Foundation

/// Per-window preview sizing (DockDoor `WindowPreviewHoverContainer.WindowDimensions`).
struct DockPreviewWindowDimensions: Equatable {
    let size: CGSize
    let maxDimensions: CGSize
}

/// Thumbnail / card sizing for dock hover (DockDoor `Window Image Sizing Calculations` subset).
enum DockPreviewDimensionEngine {
    static let dynamicMaxAspectRatio: CGFloat = 1.5
    static let dynamicSwitcherMinimumImageWidth: CGFloat = 50
    static let dynamicSwitcherMinimumCardWidth: CGFloat = 240
    static let itemSpacing: CGFloat = 24

    static func globalPaddingPerSide(multiplier: CGFloat) -> CGFloat {
        DockPreviewHoverPadding.totalPerSide(paddingMultiplier: multiplier)
    }

    struct DimensionState: Equatable {
        var overallMax: CGPoint = .zero
        var perWindow: [Int: DockPreviewWindowDimensions] = [:]
        var gridColumns: Int = 1
        var gridRows: Int = 1
    }

    static func recompute(
        entries: [DockPreviewWindowEntry],
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        screen: NSScreen,
        settings: DockPreviewSettings,
        panelSize: CGSize,
        isWindowSwitcher: Bool = false
    ) -> DimensionState {
        let overall = overallMaxDimensions(
            entries: entries,
            dockEdge: dockEdge,
            settings: settings,
            panelSize: panelSize,
            isWindowSwitcher: isWindowSwitcher
        )
        let (cols, rows) = effectiveGrid(
            screen: screen,
            overallMax: overall,
            settings: settings,
            itemCount: entries.count,
            dockEdge: dockEdge,
            isWindowSwitcher: isWindowSwitcher
        )
        let perWindow = precomputeDimensions(
            entries: entries,
            overallMax: overall,
            dockEdge: dockEdge,
            settings: settings,
            maxColumns: cols,
            maxRows: rows,
            isWindowSwitcher: isWindowSwitcher
        )
        return DimensionState(
            overallMax: overall,
            perWindow: perWindow,
            gridColumns: cols,
            gridRows: rows
        )
    }

    static func overallMaxDimensions(
        entries: [DockPreviewWindowEntry],
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        settings: DockPreviewSettings,
        panelSize: CGSize,
        isWindowSwitcher: Bool = false
    ) -> CGPoint {
        let maxW = CGFloat(settings.previewCardWidth)
        let maxH = CGFloat(settings.previewCardHeight)
        guard settings.allowDynamicImageSizing else {
            return CGPoint(x: max(1, maxW), y: max(1, maxH))
        }

        if isWindowSwitcher {
            let minImageWidth = min(maxW, dynamicSwitcherMinimumImageWidth)
            let minCardWidth = min(maxW, dynamicSwitcherMinimumCardWidth)
            var widest = minImageWidth
            for entry in entries {
                guard let image = entry.thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                let width = min(max(maxH * aspect, minImageWidth), maxW)
                widest = max(widest, width)
            }
            return CGPoint(x: max(1, min(max(widest, minCardWidth), maxW)), y: max(1, maxH))
        }

        // Thickness from settings (`getWindowSize()`), not measured panel size.
        let horizontal = dockEdge == .bottom
        let thickness: CGFloat = horizontal ? maxH : maxW
        var computedW: CGFloat = maxW
        var computedH: CGFloat = maxH
        let minAspect = 1.0 / dynamicMaxAspectRatio
        let capW = maxW * dynamicMaxAspectRatio
        let capH = maxH * dynamicMaxAspectRatio

        for entry in entries {
            guard let image = entry.thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            let cgSize = CGSize(width: image.width, height: image.height)
            guard cgSize.width > 0, cgSize.height > 0 else { continue }
            if horizontal {
                let rawW = (cgSize.width * thickness) / cgSize.height
                let w = max(min(rawW, capW), thickness * minAspect)
                computedW = max(computedW, w)
                computedH = thickness
            } else {
                let rawH = (cgSize.height * thickness) / cgSize.width
                let h = max(min(rawH, capH), thickness * minAspect)
                computedH = max(computedH, h)
                computedW = thickness
            }
        }
        return CGPoint(x: max(1, min(computedW, capW)), y: max(1, min(computedH, capH)))
    }

    static func effectiveGrid(
        screen: NSScreen,
        overallMax: CGPoint,
        settings: DockPreviewSettings,
        itemCount: Int,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        isWindowSwitcher: Bool
    ) -> (columns: Int, rows: Int) {
        let screenW = screen.visibleFrame.width
        let screenH = screen.visibleFrame.height
        let globalPadding = globalPaddingPerSide(multiplier: CGFloat(settings.globalPaddingMultiplier)) * 2
        let previewW = overallMax.x
        let previewH = overallMax.y
        let calcCols = max(1, Int((screenW - globalPadding + itemSpacing) / (previewW + itemSpacing)))
        let calcRows = max(1, Int((screenH - globalPadding + itemSpacing) / (previewH + itemSpacing)))
        let options = settings.appearanceOptions
        if isWindowSwitcher {
            if options.switcherScrollVertical {
                let cols = options.switcherIgnoreScreenLimit
                    ? options.switcherMaxRows
                    : min(options.switcherMaxRows, calcCols)
                return (max(1, cols), calcRows)
            }
            let rows = itemCount <= calcCols ? 1 : options.switcherMaxRows
            return (calcCols, max(1, rows))
        }
        if dockEdge == .bottom {
            return (calcCols, max(1, settings.previewMaxRows))
        }
        if dockEdge == .left || dockEdge == .right {
            return (min(max(1, settings.previewMaxColumns), calcCols), calcRows)
        }
        return (calcCols, calcRows)
    }

    static func precomputeDimensions(
        entries: [DockPreviewWindowEntry],
        overallMax: CGPoint,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        settings: DockPreviewSettings,
        maxColumns: Int,
        maxRows: Int,
        isWindowSwitcher: Bool
    ) -> [Int: DockPreviewWindowDimensions] {
        let maxDims = CGSize(width: overallMax.x, height: overallMax.y)
        let horizontal = isWindowSwitcher || dockEdge == .bottom
        let thickness: CGFloat = horizontal ? overallMax.y : overallMax.x
        var map: [Int: DockPreviewWindowDimensions] = [:]

        guard settings.allowDynamicImageSizing else {
            for index in entries.indices {
                map[index] = DockPreviewWindowDimensions(size: maxDims, maxDimensions: maxDims)
            }
            return map
        }

        if isWindowSwitcher {
            let minImageWidth = min(maxDims.width, dynamicSwitcherMinimumImageWidth)
            let indices = Array(entries.indices)
            let chunks = chunkArray(
                items: indices,
                isHorizontal: true,
                maxColumns: maxColumns,
                maxRows: maxRows
            )
            for chunk in chunks {
                let fittedHeights = chunk.compactMap { index -> CGFloat? in
                    guard let image = entries[index].thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        return nil
                    }
                    return computeRenderedDimension(
                        image: image,
                        thickness: thickness,
                        maxDimensions: maxDims,
                        isHorizontal: true
                    ).height
                }
                let rowHeight = min(maxDims.height, max(fittedHeights.max() ?? maxDims.height, 50))
                for index in chunk {
                    if let image = entries[index].thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let aspect = CGFloat(image.width) / CGFloat(image.height)
                        let width = min(max(rowHeight * aspect, minImageWidth), maxDims.width)
                        map[index] = DockPreviewWindowDimensions(
                            size: CGSize(width: width, height: rowHeight),
                            maxDimensions: maxDims
                        )
                    } else {
                        map[index] = DockPreviewWindowDimensions(
                            size: CGSize(width: min(300, maxDims.width), height: 36),
                            maxDimensions: maxDims
                        )
                    }
                }
            }
            return map
        }

        for (index, entry) in entries.enumerated() {
            if let image = entry.thumbnail?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let rendered = computeRenderedDimension(
                    image: image,
                    thickness: thickness,
                    maxDimensions: maxDims,
                    isHorizontal: horizontal
                )
                let size = horizontal
                    ? CGSize(width: rendered.width, height: max(rendered.height, 50))
                    : CGSize(width: max(rendered.width, 50), height: rendered.height)
                map[index] = DockPreviewWindowDimensions(size: size, maxDimensions: maxDims)
            } else {
                map[index] = DockPreviewWindowDimensions(
                    size: CGSize(width: min(300, maxDims.width), height: 36),
                    maxDimensions: maxDims
                )
            }
        }
        return map
    }

    private static func computeRenderedDimension(
        image: CGImage,
        thickness: CGFloat,
        maxDimensions: CGSize,
        isHorizontal: Bool
    ) -> CGSize {
        let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
        if isHorizontal {
            let width = min(thickness * aspectRatio, maxDimensions.width)
            return CGSize(width: width, height: thickness)
        }
        let height = min(thickness / aspectRatio, maxDimensions.height)
        return CGSize(width: thickness, height: height)
    }

    static func chunkArray<T>(
        items: [T],
        isHorizontal: Bool,
        maxColumns: Int,
        maxRows: Int,
        reverse: Bool = false,
        fillToLimit: Bool = false
    ) -> [[T]] {
        let total = items.count
        guard total > 0, maxColumns > 0, maxRows > 0 else { return [] }
        var chunks: [[T]] = []
        if isHorizontal {
            let itemsPerRow: Int
            if fillToLimit {
                itemsPerRow = maxColumns
            } else {
                let rowsNeeded = max(1, Int(ceil(Double(total) / Double(maxColumns))))
                let actualRows = min(maxRows, rowsNeeded)
                itemsPerRow = min(maxColumns, max(1, Int(ceil(Double(total) / Double(actualRows)))))
            }
            var start = 0
            while start < total {
                let end = min(start + itemsPerRow, total)
                chunks.append(Array(items[start ..< end]))
                start = end
            }
        } else {
            let itemsPerCol: Int
            if fillToLimit {
                itemsPerCol = maxRows
            } else {
                itemsPerCol = min(maxRows, Int(ceil(Double(total) / Double(min(maxColumns, total)))))
            }
            var start = 0
            while start < total {
                let end = min(start + max(itemsPerCol, 1), total)
                chunks.append(Array(items[start ..< end]))
                start = end
            }
        }
        return reverse ? chunks.reversed() : chunks
    }

    private static let estimatedEmbeddedWidgetHeight: CGFloat = 100

    /// DockDoor `PreviewStateCoordinator.computeExpectedContentSize`.
    static func computeExpectedContentSize(
        dimensionState: DimensionState,
        windowCount: Int,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        hasEmbedded: Bool,
        isWindowSwitcher: Bool,
        globalPaddingMultiplier: CGFloat,
        fillToLimit: Bool = false,
        minimumItemWidth: CGFloat = 0
    ) -> CGSize {
        guard windowCount > 0 else { return .zero }

        let isHorizontalFlow = isWindowSwitcher || dockEdge == .bottom
        let padding = DockPreviewHoverPadding.totalPerSide(paddingMultiplier: globalPaddingMultiplier)
        let cols = dimensionState.gridColumns
        let rows = dimensionState.gridRows
        let indices = Array(0 ..< windowCount)
        let chunks = chunkArray(
            items: indices,
            isHorizontal: isHorizontalFlow,
            maxColumns: cols,
            maxRows: rows,
            fillToLimit: fillToLimit
        )

        var maxItemWidth: CGFloat = 0
        var maxItemHeight: CGFloat = 0
        for dim in dimensionState.perWindow.values {
            maxItemWidth = max(maxItemWidth, max(dim.size.width, minimumItemWidth))
            maxItemHeight = max(maxItemHeight, dim.size.height)
        }

        if isHorizontalFlow {
            var maxRowWidth: CGFloat = 0
            for row in chunks {
                var rowWidth: CGFloat = 0
                for windowIndex in row {
                    let dims = dimensionState.perWindow[windowIndex]
                    let itemWidth = dims?.size.width ?? dims?.maxDimensions.width ?? 0
                    rowWidth += max(itemWidth, minimumItemWidth)
                }
                rowWidth += CGFloat(max(0, row.count - 1)) * itemSpacing
                maxRowWidth = max(maxRowWidth, rowWidth)
            }
            if hasEmbedded, let firstDims = dimensionState.perWindow[0] {
                maxRowWidth += max(firstDims.size.width, minimumItemWidth) + itemSpacing
            }
            return CGSize(
                width: maxRowWidth + padding * 2,
                height: maxItemHeight + padding * 2
            )
        }

        var maxColHeight: CGFloat = 0
        for col in chunks {
            var colHeight: CGFloat = 0
            for windowIndex in col {
                let dims = dimensionState.perWindow[windowIndex]
                colHeight += dims?.size.height ?? dims?.maxDimensions.height ?? 0
            }
            colHeight += CGFloat(max(0, col.count - 1)) * itemSpacing
            maxColHeight = max(maxColHeight, colHeight)
        }
        if hasEmbedded {
            maxColHeight += estimatedEmbeddedWidgetHeight + itemSpacing
        }
        return CGSize(
            width: maxItemWidth + padding * 2,
            height: maxColHeight + padding * 2
        )
    }
}
