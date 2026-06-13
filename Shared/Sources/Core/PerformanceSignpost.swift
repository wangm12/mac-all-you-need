import Foundation
import os

/// Lightweight os_signpost helpers for Instruments (Points of Interest).
public enum PerformanceSignpost {
    private static let clipboardLog = OSLog(
        subsystem: Logging.subsystem(for: "clipboard"),
        category: "search"
    )
    private static let dockLog = OSLog(
        subsystem: Logging.subsystem(for: "dock-previews"),
        category: "capture"
    )

    public enum Clipboard {
        public static func beginHistoryLoad() -> OSSignpostID {
            let id = OSSignpostID(log: clipboardLog)
            os_signpost(.begin, log: clipboardLog, name: "ClipboardHistoryLoad", signpostID: id)
            return id
        }

        public static func endHistoryLoad(_ id: OSSignpostID) {
            os_signpost(.end, log: clipboardLog, name: "ClipboardHistoryLoad", signpostID: id)
        }
    }

    public enum DockCapture {
        public static func beginRefreshApp(pid: pid_t) -> OSSignpostID {
            let id = OSSignpostID(log: dockLog)
            os_signpost(
                .begin,
                log: dockLog,
                name: "DockRefreshApp",
                signpostID: id,
                "pid=%d",
                pid
            )
            return id
        }

        public static func endRefreshApp(_ id: OSSignpostID) {
            os_signpost(.end, log: dockLog, name: "DockRefreshApp", signpostID: id)
        }

        public static func beginDiskHydrate(count: Int) -> OSSignpostID {
            let id = OSSignpostID(log: dockLog)
            os_signpost(
                .begin,
                log: dockLog,
                name: "DockDiskHydrate",
                signpostID: id,
                "entries=%d",
                count
            )
            return id
        }

        public static func endDiskHydrate(_ id: OSSignpostID) {
            os_signpost(.end, log: dockLog, name: "DockDiskHydrate", signpostID: id)
        }

        public static func beginHoverShow(pid: pid_t) -> OSSignpostID {
            let id = OSSignpostID(log: dockLog)
            os_signpost(
                .begin,
                log: dockLog,
                name: "DockHoverShow",
                signpostID: id,
                "pid=%d",
                pid
            )
            return id
        }

        public static func endHoverShow(_ id: OSSignpostID) {
            os_signpost(.end, log: dockLog, name: "DockHoverShow", signpostID: id)
        }

        public static func beginFirstThumbnailRender(count: Int) -> OSSignpostID {
            let id = OSSignpostID(log: dockLog)
            os_signpost(
                .begin,
                log: dockLog,
                name: "DockFirstThumbnail",
                signpostID: id,
                "entries=%d",
                count
            )
            return id
        }

        public static func endFirstThumbnailRender(_ id: OSSignpostID) {
            os_signpost(.end, log: dockLog, name: "DockFirstThumbnail", signpostID: id)
        }
    }
}
