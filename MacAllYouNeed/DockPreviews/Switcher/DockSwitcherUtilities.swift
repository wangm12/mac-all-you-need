import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum DockSwitcherUtilities {
    static func shouldIgnoreKeybind(blacklist: [String]) -> Bool {
        guard !blacklist.isEmpty,
              let app = NSWorkspace.shared.frontmostApplication
        else { return false }
        guard DockPreviewFullscreenDetection.isAppFullscreen(app) else { return false }
        let name = app.localizedName ?? ""
        let bundle = app.bundleIdentifier ?? ""
        return blacklist.contains { filter in
            let f = filter.lowercased()
            return name.lowercased().contains(f) || bundle.lowercased().contains(f)
        }
    }

    static func warpMouseToWindowCenter(
        entry: DockPreviewWindowEntry,
        mode: DockSwitcherMouseFollowsFocus
    ) {
        guard mode != .never else { return }
        let center = CGPoint(x: entry.frame.midX, y: entry.frame.midY)
        let screenForWindow = screenContainingQuartzPoint(center)
        let screenForMouse = screenContainingPoint(NSEvent.mouseLocation)
        if mode == .differentDisplayOnly, screenForWindow == screenForMouse { return }
        let nsCenter = quartzToScreenPoint(center, screen: screenForWindow)
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(nsCenter)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    static func vimKeyCode(for character: Character) -> UInt16? {
        switch character {
        case "h": return UInt16(kVK_ANSI_H)
        case "j": return UInt16(kVK_ANSI_J)
        case "k": return UInt16(kVK_ANSI_K)
        case "l": return UInt16(kVK_ANSI_L)
        default: return nil
        }
    }

    private static func screenContainingQuartzPoint(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            quartzScreenFrame(screen).contains(point)
        } ?? NSScreen.main
    }

    private static func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private static func quartzScreenFrame(_ screen: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return screen.frame }
        let h = primary.frame.height
        return CGRect(
            x: screen.frame.origin.x,
            y: h - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private static func quartzToScreenPoint(_ quartz: CGPoint, screen: NSScreen?) -> CGPoint {
        guard let screen, let primary = NSScreen.screens.first else { return quartz }
        let h = primary.frame.height
        return CGPoint(x: quartz.x, y: h - quartz.y)
    }
}
