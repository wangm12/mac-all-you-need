import CoreGraphics
import Foundation

struct DockTriggerZone: Equatable {
    let rect: CGRect
    let nudgeVector: CGVector
}

struct DockEdgeInterval: Equatable {
    let start: CGFloat
    let end: CGFloat
    var length: CGFloat { end - start }

    static func merge(_ intervals: [DockEdgeInterval]) -> [DockEdgeInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged = [sorted[0]]
        for interval in sorted.dropFirst() {
            if interval.start <= merged[merged.count - 1].end + 0.5 {
                let last = merged[merged.count - 1]
                merged[merged.count - 1] = DockEdgeInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func subtract(from full: DockEdgeInterval, removing covered: [DockEdgeInterval]) -> [DockEdgeInterval] {
        let merged = merge(covered)
        var result: [DockEdgeInterval] = []
        var cursor = full.start
        for interval in merged {
            if interval.start > cursor {
                let gap = DockEdgeInterval(start: cursor, end: min(interval.start, full.end))
                if gap.length > 0.5 { result.append(gap) }
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < full.end {
            let remaining = DockEdgeInterval(start: cursor, end: full.end)
            if remaining.length > 0.5 { result.append(remaining) }
        }
        return result
    }
}

enum DockLockerGeometry {
    private static let triggerDepth: CGFloat = 7
    private static let adjacencyTolerance: CGFloat = 2

    static func calculateTriggerZones(
        screenFrames: [CGRect],
        lockedScreenIndex: Int,
        dockEdge: DockPreviewPanelGeometry.DockEdge
    ) -> [DockTriggerZone] {
        guard screenFrames.count > 1,
              lockedScreenIndex >= 0,
              lockedScreenIndex < screenFrames.count
        else { return [] }

        var zones: [DockTriggerZone] = []
        for (index, frame) in screenFrames.enumerated() where index != lockedScreenIndex {
            let intervals = exposedIntervals(for: frame, dockEdge: dockEdge, allFrames: screenFrames)
            for interval in intervals {
                if let zone = triggerZone(for: frame, interval: interval, dockEdge: dockEdge) {
                    zones.append(zone)
                }
            }
        }
        return zones
    }

    static func exposedIntervals(
        for frame: CGRect,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        allFrames: [CGRect]
    ) -> [DockEdgeInterval] {
        let (edgePosition, fullInterval) = edgeInfo(for: frame, dockEdge: dockEdge)
        var covered: [DockEdgeInterval] = []
        for other in allFrames where other != frame {
            guard isAdjacent(other, to: frame, dockEdge: dockEdge, edgePosition: edgePosition) else { continue }
            let otherInterval = perpendicularInterval(of: other, dockEdge: dockEdge)
            let overlapStart = max(fullInterval.start, otherInterval.start)
            let overlapEnd = min(fullInterval.end, otherInterval.end)
            if overlapEnd - overlapStart > 0.5 {
                covered.append(DockEdgeInterval(start: overlapStart, end: overlapEnd))
            }
        }
        return DockEdgeInterval.subtract(from: fullInterval, removing: covered)
    }

    private static func edgeInfo(
        for frame: CGRect,
        dockEdge: DockPreviewPanelGeometry.DockEdge
    ) -> (CGFloat, DockEdgeInterval) {
        switch dockEdge {
        case .bottom:
            (frame.maxY, DockEdgeInterval(start: frame.minX, end: frame.maxX))
        case .left:
            (frame.minX, DockEdgeInterval(start: frame.minY, end: frame.maxY))
        case .right:
            (frame.maxX, DockEdgeInterval(start: frame.minY, end: frame.maxY))
        }
    }

    private static func isAdjacent(
        _ other: CGRect,
        to frame: CGRect,
        dockEdge: DockPreviewPanelGeometry.DockEdge,
        edgePosition: CGFloat
    ) -> Bool {
        switch dockEdge {
        case .bottom:
            abs(other.maxY - edgePosition) <= adjacencyTolerance && other.maxX > frame.minX && other.minX < frame.maxX
        case .left:
            abs(other.minX - edgePosition) <= adjacencyTolerance && other.maxY > frame.minY && other.minY < frame.maxY
        case .right:
            abs(other.maxX - edgePosition) <= adjacencyTolerance && other.maxY > frame.minY && other.minY < frame.maxY
        }
    }

    private static func perpendicularInterval(of frame: CGRect, dockEdge: DockPreviewPanelGeometry.DockEdge) -> DockEdgeInterval {
        switch dockEdge {
        case .bottom:
            DockEdgeInterval(start: frame.minX, end: frame.maxX)
        case .left, .right:
            DockEdgeInterval(start: frame.minY, end: frame.maxY)
        }
    }

    private static func triggerZone(
        for frame: CGRect,
        interval: DockEdgeInterval,
        dockEdge: DockPreviewPanelGeometry.DockEdge
    ) -> DockTriggerZone? {
        guard interval.length > 0.5 else { return nil }
        switch dockEdge {
        case .bottom:
            let rect = CGRect(
                x: interval.start,
                y: frame.maxY - triggerDepth,
                width: interval.length,
                height: triggerDepth
            )
            return DockTriggerZone(rect: rect, nudgeVector: CGVector(dx: 0, dy: -triggerDepth))
        case .left:
            let rect = CGRect(
                x: frame.minX,
                y: interval.start,
                width: triggerDepth,
                height: interval.length
            )
            return DockTriggerZone(rect: rect, nudgeVector: CGVector(dx: -triggerDepth, dy: 0))
        case .right:
            let rect = CGRect(
                x: frame.maxX - triggerDepth,
                y: interval.start,
                width: triggerDepth,
                height: interval.length
            )
            return DockTriggerZone(rect: rect, nudgeVector: CGVector(dx: triggerDepth, dy: 0))
        }
    }
}
