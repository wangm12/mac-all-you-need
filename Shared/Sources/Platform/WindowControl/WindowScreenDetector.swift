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

    /// Union of all display frames in CG display coordinates.
    public static func desktopBounds(for screens: [WindowControlScreen]) -> CGRect {
        screens.map(\.frame).reduce(CGRect.null) { partial, frame in
            partial.isNull ? frame : partial.union(frame)
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

    /// AppKit `NSScreen.frame` paired with `CGDisplayBounds` for each display.
    public struct ScreenLayoutPair: Equatable, Sendable {
        public let appKitFrame: CGRect
        public let cgBounds: CGRect

        public init(appKitFrame: CGRect, cgBounds: CGRect) {
            self.appKitFrame = appKitFrame
            self.cgBounds = cgBounds
        }
    }

    /// Live display layout for coordinate conversion (refreshed on each call).
    public static func currentScreenLayout() -> [ScreenLayoutPair] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value ?? UInt32(index)
            return ScreenLayoutPair(appKitFrame: screen.frame, cgBounds: CGDisplayBounds(id))
        }
    }

    /// Converts a global point from CG display coordinates (top-left origin) to AppKit desktop coordinates.
    public static func appKitPoint(fromCG point: CGPoint, layout: [ScreenLayoutPair] = currentScreenLayout()) -> CGPoint {
        if let pair = layout.first(where: { $0.cgBounds.contains(point) }) {
            return appKitPoint(fromCG: point, appKitScreenFrame: pair.appKitFrame, cgDisplayBounds: pair.cgBounds)
        }
        if let pair = nearestLayoutPair(to: point, in: layout, space: .cg) {
            return appKitPoint(fromCG: point, appKitScreenFrame: pair.appKitFrame, cgDisplayBounds: pair.cgBounds)
        }
        return legacyFlippedAppKitPoint(fromCG: point, layout: layout)
    }

    /// Converts a global point from AppKit desktop coordinates to CG display coordinates.
    public static func cgPoint(fromAppKit point: CGPoint, layout: [ScreenLayoutPair] = currentScreenLayout()) -> CGPoint {
        if let pair = layout.first(where: { $0.appKitFrame.contains(point) }) {
            return cgPoint(fromAppKit: point, appKitScreenFrame: pair.appKitFrame, cgDisplayBounds: pair.cgBounds)
        }
        if let pair = nearestLayoutPair(to: point, in: layout, space: .appKit) {
            return cgPoint(fromAppKit: point, appKitScreenFrame: pair.appKitFrame, cgDisplayBounds: pair.cgBounds)
        }
        return legacyFlippedCGPoint(fromAppKit: point, layout: layout)
    }

    public static func appKitPoint(
        fromCG point: CGPoint,
        appKitScreenFrame: CGRect,
        cgDisplayBounds: CGRect
    ) -> CGPoint {
        CGPoint(
            x: appKitScreenFrame.minX + (point.x - cgDisplayBounds.minX),
            y: appKitScreenFrame.maxY - (point.y - cgDisplayBounds.minY)
        )
    }

    public static func cgPoint(
        fromAppKit point: CGPoint,
        appKitScreenFrame: CGRect,
        cgDisplayBounds: CGRect
    ) -> CGPoint {
        CGPoint(
            x: cgDisplayBounds.minX + (point.x - appKitScreenFrame.minX),
            y: cgDisplayBounds.minY + (appKitScreenFrame.maxY - point.y)
        )
    }

    private enum LayoutCoordinateSpace {
        case cg
        case appKit
    }

    private static func nearestLayoutPair(
        to point: CGPoint,
        in layout: [ScreenLayoutPair],
        space: LayoutCoordinateSpace
    ) -> ScreenLayoutPair? {
        layout.min { lhs, rhs in
            distanceSquared(from: point, to: space == .cg ? lhs.cgBounds : lhs.appKitFrame)
                < distanceSquared(from: point, to: space == .cg ? rhs.cgBounds : rhs.appKitFrame)
        }
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
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

    private static func legacyFlippedAppKitPoint(fromCG point: CGPoint, layout: [ScreenLayoutPair]) -> CGPoint {
        let globalHeight = layout.map(\.appKitFrame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: globalHeight - point.y)
    }

    private static func legacyFlippedCGPoint(fromAppKit point: CGPoint, layout: [ScreenLayoutPair]) -> CGPoint {
        let globalHeight = layout.map(\.appKitFrame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: globalHeight - point.y)
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

/// Reads the current `NSScreen` layout on every access so hot-plug and arrangement
/// changes are visible without restarting the app.
public struct LiveWindowScreenDetector: WindowScreenDetecting, Sendable {
    public init() {}

    private var snapshot: WindowScreenDetector {
        WindowScreenDetector.current()
    }

    public var screens: [WindowControlScreen] {
        snapshot.screens
    }

    public func screen(containing frame: CGRect) -> WindowControlScreen? {
        snapshot.screen(containing: frame)
    }

    public func screen(containing point: CGPoint) -> WindowControlScreen? {
        snapshot.screen(containing: point)
    }

    public func nextScreen(after screen: WindowControlScreen) -> WindowControlScreen? {
        snapshot.nextScreen(after: screen)
    }

    public func previousScreen(before screen: WindowControlScreen) -> WindowControlScreen? {
        snapshot.previousScreen(before: screen)
    }
}
