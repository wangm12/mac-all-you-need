import AppKit
import ApplicationServices
import CoreGraphics

public protocol WindowTargetElement: WindowMovableElement {
    var processIdentifier: pid_t { get }
    var windowTargetSelectionPriority: Int { get }
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

            guard let element = selectBestCandidate(matches, at: point) else {
                continue
            }

            return ResolvedWindowTarget(windowID: info.windowID, windowInfo: info, element: element)
        }

        return nil
    }

    public func resolveTopmostWindow(at point: CGPoint) -> ResolvedWindowTarget? {
        // 1. Ask Accessibility for the element directly under the cursor and
        //    walk up to its enclosing AXWindow. This handles Stage Manager
        //    strips, occluded windows, and full-screen Spaces where the
        //    CGWindowList-based path below routinely picks the wrong window.
        if let viaSystemWide = resolveViaSystemWideAX(at: point) {
            return viaSystemWide
        }

        // 2. Fallback: CGWindowList front-to-back + AX windows matched by frame.
        let windows = Self.currentOnScreenWindows()
        let processIdentifiers = Set(windows.map(\.processIdentifier))
        let candidates = processIdentifiers.flatMap { WindowAccessibilityElement.windows(for: $0) }
        return resolveTopmostWindow(at: point, windows: windows, candidates: candidates)
    }

    private func resolveViaSystemWideAX(at point: CGPoint) -> ResolvedWindowTarget? {
        guard visibleFrames.isEmpty || visibleFrames.contains(where: { $0.contains(point) }) else {
            return nil
        }

        var rawElement: AXUIElement?
        let lookup = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(point.x),
            Float(point.y),
            &rawElement
        )
        guard lookup == .success, let rawElement, let windowAX = enclosingWindow(of: rawElement) else {
            return nil
        }

        let wrapper = WindowAccessibilityElement(windowAX)
        guard wrapper.isSupportedForWindowControl else {
            return nil
        }

        let wrapperFrame = wrapper.frame
        guard wrapperFrame.contains(point) else {
            return nil
        }

        let pid = wrapper.processIdentifier
        let info = Self.currentOnScreenWindows().first { candidate in
            candidate.processIdentifier == pid
                && candidate.layer == 0
                && !candidate.isDesktopElement
                && candidate.bounds.contains(point)
                && frame(wrapperFrame, matches: candidate.bounds)
        }

        let resolvedInfo = info ?? WindowTargetWindowInfo(
            windowID: 0,
            processIdentifier: pid,
            bounds: wrapperFrame,
            layer: 0,
            ownerBundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
            isDesktopElement: false
        )

        return ResolvedWindowTarget(windowID: resolvedInfo.windowID, windowInfo: resolvedInfo, element: wrapper)
    }

    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<10 {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String, role == "AXWindow" {
                return current
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID()
            else {
                return nil
            }
            current = parentValue as! AXUIElement
        }
        return nil
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
        return true
    }

    private func frame(_ lhs: CGRect, matches rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= frameTolerance
            && abs(lhs.minY - rhs.minY) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
    }

    /// Finder / Notes / iTerm can expose several AXWindow elements for one CG window.
    private func selectBestCandidate(
        _ matches: [any WindowTargetElement],
        at point: CGPoint
    ) -> (any WindowTargetElement)? {
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 { return matches[0] }

        let containingPoint = matches.filter { candidate in
            let frame = candidate.frame
            return !frame.isNull && !frame.isEmpty && frame.contains(point)
        }
        let pool = containingPoint.isEmpty ? matches : containingPoint

        return pool.max { lhs, rhs in
            let lhsPriority = lhs.windowTargetSelectionPriority
            let rhsPriority = rhs.windowTargetSelectionPriority
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            return lhsArea < rhsArea
        }
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
