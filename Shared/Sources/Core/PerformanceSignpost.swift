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

    public enum WindowControl {
        private static let log = OSLog(
            subsystem: Logging.subsystem(for: "windowcontrol"),
            category: "move"
        )

        public static func beginResolveWindow() -> OSSignpostID {
            let id = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "ResolveWindow", signpostID: id)
            return id
        }

        public static func endResolveWindow(_ id: OSSignpostID) {
            os_signpost(.end, log: log, name: "ResolveWindow", signpostID: id)
        }

        public static func beginCalculateFrame(action: String) -> OSSignpostID {
            let id = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "CalculateFrame", signpostID: id, "action=%{public}s", action)
            return id
        }

        public static func endCalculateFrame(_ id: OSSignpostID) {
            os_signpost(.end, log: log, name: "CalculateFrame", signpostID: id)
        }

        public static func beginAXWrite() -> OSSignpostID {
            let id = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "AXWrite", signpostID: id)
            return id
        }

        public static func endAXWrite(_ id: OSSignpostID) {
            os_signpost(.end, log: log, name: "AXWrite", signpostID: id)
        }
    }
}
