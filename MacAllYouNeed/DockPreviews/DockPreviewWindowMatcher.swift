import CoreGraphics
import Foundation

/// Merges AX window data (title, minimized state) with SCK window IDs (for capture).
/// Pure: no I/O, no AppKit.
enum DockPreviewWindowMatcher {
    struct AXWindowInfo {
        let title: String
        let isMinimized: Bool
        let frame: CGRect
    }

    struct SCWindowInfo {
        let windowID: CGWindowID
        let frame: CGRect
        let pid: pid_t
    }

    /// Matches SC windows to AX windows by frame proximity.
    static func merge(ax: [AXWindowInfo], sc: [SCWindowInfo], pid: pid_t) -> [DockPreviewWindowEntry] {
        var result: [DockPreviewWindowEntry] = []

        // Match by frame overlap (nearest centroid)
        for scWin in sc {
            let bestAX = ax.min(by: {
                centroidDistance($0.frame, scWin.frame) < centroidDistance($1.frame, scWin.frame)
            })
            let title = bestAX?.title ?? "(Window \(scWin.windowID))"
            let isMinimized = bestAX?.isMinimized ?? false
            result.append(DockPreviewWindowEntry(
                id: scWin.windowID, pid: pid, title: title,
                frame: scWin.frame, thumbnail: nil,
                isMinimized: isMinimized, isOnScreen: true
            ))
        }
        // Add minimized-only AX windows (not in SC list)
        for axWin in ax where axWin.isMinimized {
            if !result.contains(where: { $0.frame == axWin.frame }) {
                result.append(DockPreviewWindowEntry(
                    id: CGWindowID(result.count + 10000), pid: pid,
                    title: axWin.title, frame: axWin.frame, thumbnail: nil,
                    isMinimized: true, isOnScreen: false
                ))
            }
        }
        return result
    }

    static func centroidDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = a.midX - b.midX
        let dy = a.midY - b.midY
        return sqrt(dx * dx + dy * dy)
    }
}
