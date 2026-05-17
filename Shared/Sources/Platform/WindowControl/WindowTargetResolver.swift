import AppKit
import CoreGraphics

public protocol WindowTargetElement: WindowMovableElement {
    var processIdentifier: pid_t { get }
}

public struct WindowTargetWindowInfo: Equatable, Sendable {
    public let windowID: CGWindowID
    public let processIdentifier: pid_t
    public let bounds: CGRect
    public let layer: Int
    public let ownerBundleIdentifier: String?
    public let isDesktopElement: Bool

    public init(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        bounds: CGRect,
        layer: Int,
        ownerBundleIdentifier: String?,
        isDesktopElement: Bool
    ) {
        self.windowID = windowID
        self.processIdentifier = processIdentifier
        self.bounds = bounds
        self.layer = layer
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.isDesktopElement = isDesktopElement
    }
}

public struct ResolvedWindowTarget {
    public let windowID: CGWindowID
    public let windowInfo: WindowTargetWindowInfo
    public let element: any WindowTargetElement

    public init(windowID: CGWindowID, windowInfo: WindowTargetWindowInfo, element: any WindowTargetElement) {
        self.windowID = windowID
        self.windowInfo = windowInfo
        self.element = element
    }
}

public struct WindowTargetResolver {
    private let ownBundleIdentifier: String?
    private let visibleFrames: [CGRect]
    private let frameTolerance: CGFloat

    public init(
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        visibleFrames: [CGRect] = WindowScreenDetector.current().screens.map(\.visibleFrame),
        frameTolerance: CGFloat = 6
    ) {
        self.ownBundleIdentifier = ownBundleIdentifier
        self.visibleFrames = visibleFrames
        self.frameTolerance = frameTolerance
    }

    public func resolveTopmostWindow<Candidates: Collection>(
        at point: CGPoint,
        windows: [WindowTargetWindowInfo],
        candidates: Candidates
    ) -> ResolvedWindowTarget? where Candidates.Element: WindowTargetElement {
        guard visibleFrames.isEmpty || visibleFrames.contains(where: { $0.contains(point) }) else {
            return nil
        }

        for info in windows where isEligible(info, at: point) {
            let matches = candidates.filter { candidate in
                candidate.processIdentifier == info.processIdentifier
                    && candidate.isSupportedForWindowControl
                    && frame(candidate.frame, matches: info.bounds)
            }

            guard matches.count == 1, let element = matches.first else {
                return nil
            }

            return ResolvedWindowTarget(windowID: info.windowID, windowInfo: info, element: element)
        }

        return nil
    }

    public func resolveTopmostWindow(at point: CGPoint) -> ResolvedWindowTarget? {
        let windows = Self.currentOnScreenWindows()
        let processIdentifiers = Set(windows.map(\.processIdentifier))
        let candidates = processIdentifiers.flatMap { WindowAccessibilityElement.windows(for: $0) }
        return resolveTopmostWindow(at: point, windows: windows, candidates: candidates)
    }

    public static func currentOnScreenWindows() -> [WindowTargetWindowInfo] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap(WindowTargetWindowInfo.init(dictionary:))
    }

    private func isEligible(_ info: WindowTargetWindowInfo, at point: CGPoint) -> Bool {
        guard info.layer == 0,
              !info.isDesktopElement,
              info.bounds.contains(point)
        else {
            return false
        }
        if let ownBundleIdentifier, info.ownerBundleIdentifier == ownBundleIdentifier {
            return false
        }
        return true
    }

    private func frame(_ lhs: CGRect, matches rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= frameTolerance
            && abs(lhs.minY - rhs.minY) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
    }
}

private extension WindowTargetWindowInfo {
    init?(dictionary: [String: Any]) {
        guard let windowID = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let processIdentifier = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        else {
            return nil
        }

        let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let bundleID = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
        self.init(
            windowID: windowID,
            processIdentifier: processIdentifier,
            bounds: bounds,
            layer: layer,
            ownerBundleIdentifier: bundleID,
            isDesktopElement: false
        )
    }
}
