import AppKit
import Foundation

enum DockPreviewWindowFilter {
    static func filter(_ entries: [DockPreviewWindowEntry], settings: DockPreviewSettings) -> [DockPreviewWindowEntry] {
        entries.filter { entry in
            if entry.isOnScreen { return true }
            if settings.includeHiddenMinimized, entry.isMinimized { return true }
            return false
        }
    }

    static func filterByMonitor(
        _ entries: [DockPreviewWindowEntry],
        dockIconRect: CGRect,
        settings: DockPreviewSettings
    ) -> [DockPreviewWindowEntry] {
        guard settings.currentMonitorOnly else { return entries }
        guard let screen = screenForQuartzRect(dockIconRect) else { return entries }
        return entries.filter { screen.frame.intersects(quartzRectToScreenFrame($0.frame, screen: screen)) }
    }

    private static func screenForQuartzRect(_ rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { screen in
            let screenQuartz = screenFrameInQuartz(screen)
            return screenQuartz.contains(center)
        } ?? NSScreen.main
    }

    private static func screenFrameInQuartz(_ screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: screen.frame.origin.x,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private static func quartzRectToScreenFrame(_ quartz: CGRect, screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return quartz }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: quartz.origin.x,
            y: primaryHeight - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }
}
