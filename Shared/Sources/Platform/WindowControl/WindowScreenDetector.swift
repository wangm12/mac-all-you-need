import AppKit
import CoreGraphics

public struct WindowControlScreen: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public protocol WindowScreenDetecting {
    var screens: [WindowControlScreen] { get }
    func screen(containing frame: CGRect) -> WindowControlScreen?
    func screen(containing point: CGPoint) -> WindowControlScreen?
    func nextScreen(after screen: WindowControlScreen) -> WindowControlScreen?
    func previousScreen(before screen: WindowControlScreen) -> WindowControlScreen?
}

public struct WindowScreenDetector: WindowScreenDetecting, Sendable {
    public let screens: [WindowControlScreen]

    public init(screens: [WindowControlScreen]) {
        self.screens = screens
    }

    public static func current() -> WindowScreenDetector {
        WindowScreenDetector(screens: traversalOrderedScreens(NSScreen.screens.enumerated().map { index, screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value ?? UInt32(index)
            let cgDisplayBounds = CGDisplayBounds(id)
            return WindowControlScreen(
                id: id,
                frame: cgDisplayBounds,
                visibleFrame: convertAppKitRectToCGDisplayCoordinates(
                    appKitRect: screen.visibleFrame,
                    appKitScreenFrame: screen.frame,
                    cgDisplayBounds: cgDisplayBounds
                )
            )
        }))
    }

    public static func traversalOrderedScreens(_ screens: [WindowControlScreen]) -> [WindowControlScreen] {
        screens.sorted { lhs, rhs in
            if lhs.frame.maxY <= rhs.frame.minY {
                return true
            }
            if rhs.frame.maxY <= lhs.frame.minY {
                return false
            }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    static func convertAppKitRectToCGDisplayCoordinates(
        appKitRect: CGRect,
        appKitScreenFrame: CGRect,
        cgDisplayBounds: CGRect
    ) -> CGRect {
        CGRect(
            x: cgDisplayBounds.minX + appKitRect.minX - appKitScreenFrame.minX,
            y: cgDisplayBounds.minY + appKitScreenFrame.maxY - appKitRect.maxY,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    public static func convertCGDisplayRectToAppKitCoordinates(
        cgRect: CGRect,
        appKitScreenFrame: CGRect,
        cgDisplayBounds: CGRect
    ) -> CGRect {
        CGRect(
            x: appKitScreenFrame.minX + cgRect.minX - cgDisplayBounds.minX,
            y: appKitScreenFrame.maxY - (cgRect.maxY - cgDisplayBounds.minY),
            width: cgRect.width,
            height: cgRect.height
        )
    }

    public func screen(containing frame: CGRect) -> WindowControlScreen? {
        guard !screens.isEmpty else { return nil }

        let intersecting = screens
            .map { screen in (screen, area(frame.intersection(screen.frame))) }
            .filter { $0.1 > 0 }
            .max { lhs, rhs in lhs.1 < rhs.1 }
        if let intersecting {
            return intersecting.0
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return nearestScreen(to: center)
    }

    public func screen(containing point: CGPoint) -> WindowControlScreen? {
        if let containing = screens.first(where: { $0.frame.contains(point) }) {
            return containing
        }
        return nearestScreen(to: point)
    }

    public func nextScreen(after screen: WindowControlScreen) -> WindowControlScreen? {
        guard let index = screens.firstIndex(of: screen), screens.count > 1 else {
            return nil
        }
        return screens[(index + 1) % screens.count]
    }

    public func previousScreen(before screen: WindowControlScreen) -> WindowControlScreen? {
        guard let index = screens.firstIndex(of: screen), screens.count > 1 else {
            return nil
        }
        return screens[(index - 1 + screens.count) % screens.count]
    }

    private func nearestScreen(to point: CGPoint) -> WindowControlScreen? {
        screens.min { lhs, rhs in
            distanceSquared(from: point, to: lhs.frame) < distanceSquared(from: point, to: rhs.frame)
        }
    }

    private func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else {
            return 0
        }
        return rect.width * rect.height
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }
}
