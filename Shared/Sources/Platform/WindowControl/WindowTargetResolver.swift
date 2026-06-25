import AppKit
import ApplicationServices
import CoreGraphics

public protocol WindowTargetElement: WindowMovableElement {
    var processIdentifier: pid_t { get }
    var windowTargetSelectionPriority: Int { get }
    /// When available, the CGWindowID backing this AX element.
    var cgWindowID: CGWindowID? { get }
    /// True when the element exposes standard window chrome (zoom/close).
    var hasStandardWindowControls: Bool { get }
}

public extension WindowTargetElement {
    var cgWindowID: CGWindowID? { nil }
    var hasStandardWindowControls: Bool { false }
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

public struct WindowTargetResolveOptions: Sendable {
    /// When false, skips `AXUIElementCopyElementAtPosition` (event-tap safe path).
    public var useSystemWideAX: Bool
    /// When false, windows owned by this app are skipped so grabs pass through to apps behind.
    public var includeOwnApplication: Bool

    public init(useSystemWideAX: Bool = true, includeOwnApplication: Bool = false) {
        self.useSystemWideAX = useSystemWideAX
        self.includeOwnApplication = includeOwnApplication
    }

    public static let full = WindowTargetResolveOptions()
    public static let eventTap = WindowTargetResolveOptions(useSystemWideAX: false)
    public static let grabGesture = WindowTargetResolveOptions(useSystemWideAX: false, includeOwnApplication: true)
}

public struct WindowTargetResolver {
    private let ownBundleIdentifier: String?
    private let visibleFramesProvider: @Sendable () -> [CGRect]
    private let frameTolerance: CGFloat

    public init(
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        visibleFrames: [CGRect]? = nil,
        frameTolerance: CGFloat = 6
    ) {
        self.ownBundleIdentifier = ownBundleIdentifier
        if let visibleFrames {
            let snapshot = visibleFrames
            self.visibleFramesProvider = { snapshot }
        } else {
            self.visibleFramesProvider = {
                WindowScreenDetector.current().screens.map(\.visibleFrame)
            }
        }
        self.frameTolerance = frameTolerance
    }

    public func resolveTopmostWindow<Candidates: Collection>(
        at point: CGPoint,
        windows: [WindowTargetWindowInfo],
        candidates: Candidates,
        options: WindowTargetResolveOptions = .full
    ) -> ResolvedWindowTarget? where Candidates.Element: WindowTargetElement {
        guard liveVisibleFrames.isEmpty || liveVisibleFrames.contains(where: { $0.contains(point) }) else {
            return nil
        }

        for info in windows where isEligible(info, at: point, options: options) {
            let matches = candidates.filter { candidate in
                candidate.processIdentifier == info.processIdentifier
                    && candidate.isSupportedForWindowControl
                    && frame(candidate.frame, matches: info.bounds)
            }

            guard let element = selectBestCandidate(
                matches,
                at: point,
                preferredWindowID: info.windowID,
                ownerBundleIdentifier: info.ownerBundleIdentifier
            ) else {
                continue
            }

            return ResolvedWindowTarget(windowID: info.windowID, windowInfo: info, element: element)
        }

        return nil
    }

    public func resolveTopmostWindow(
        at point: CGPoint,
        options: WindowTargetResolveOptions = .full
    ) -> ResolvedWindowTarget? {
        // 1. Ask Accessibility for the element directly under the cursor and
        //    walk up to its enclosing AXWindow. This handles Stage Manager
        //    strips, occluded windows, and full-screen Spaces where the
        //    CGWindowList-based path below routinely picks the wrong window.
        if options.useSystemWideAX, let viaSystemWide = resolveViaSystemWideAX(at: point) {
            return viaSystemWide
        }

        // 2. Fallback: CGWindowList front-to-back + AX windows matched by frame.
        let windows = Self.currentOnScreenWindows()
        return resolveTopmostWindowViaCGWindowList(at: point, windows: windows, options: options)
    }

    /// CGWindowList-only hit test for lightweight event-tap pre-checks.
    public func topmostWindowInfo(
        at point: CGPoint,
        options: WindowTargetResolveOptions = .full
    ) -> WindowTargetWindowInfo? {
        guard liveVisibleFrames.isEmpty || liveVisibleFrames.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return Self.currentOnScreenWindows().first { isEligible($0, at: point, options: options) }
    }

    private func resolveTopmostWindowViaCGWindowList(
        at point: CGPoint,
        windows: [WindowTargetWindowInfo],
        options: WindowTargetResolveOptions
    ) -> ResolvedWindowTarget? {
        for info in windows where isEligible(info, at: point, options: options) {
            if let bundleID = info.ownerBundleIdentifier,
               WindowAXShellResolver.isBrowserBundle(bundleID),
               let shell = WindowAXShellResolver.shellElement(
                   processIdentifier: info.processIdentifier,
                   windowID: info.windowID,
                   ownerBundleIdentifier: bundleID
               ),
               shell.isSupportedForWindowControl
            {
                return ResolvedWindowTarget(windowID: info.windowID, windowInfo: info, element: shell)
            }

            let candidates = WindowAccessibilityElement.windows(for: info.processIdentifier)
            guard let element = selectBestCandidate(
                candidates.filter { candidate in
                    candidate.isSupportedForWindowControl
                        && frame(candidate.frame, matches: info.bounds)
                },
                at: point,
                preferredWindowID: info.windowID,
                ownerBundleIdentifier: info.ownerBundleIdentifier
            ) else {
                continue
            }
            return ResolvedWindowTarget(windowID: info.windowID, windowInfo: info, element: element)
        }
        return nil
    }

    private var liveVisibleFrames: [CGRect] {
        visibleFramesProvider()
    }

    private func resolveViaSystemWideAX(at point: CGPoint) -> ResolvedWindowTarget? {
        guard liveVisibleFrames.isEmpty || liveVisibleFrames.contains(where: { $0.contains(point) }) else {
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

    private func isEligible(
        _ info: WindowTargetWindowInfo,
        at point: CGPoint,
        options: WindowTargetResolveOptions
    ) -> Bool {
        guard info.layer == 0,
              !info.isDesktopElement,
              info.bounds.contains(point)
        else {
            return false
        }
        if !options.includeOwnApplication,
           let ownBundleIdentifier,
           let owner = info.ownerBundleIdentifier,
           owner.caseInsensitiveCompare(ownBundleIdentifier) == .orderedSame
        {
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

    /// Tie-breaker when multiple AX windows match one CG window (Finder, Notes, iTerm, Chrome tabs).
    private func selectBestCandidate(
        _ matches: [any WindowTargetElement],
        at point: CGPoint,
        preferredWindowID: CGWindowID,
        ownerBundleIdentifier: String?
    ) -> (any WindowTargetElement)? {
        guard !matches.isEmpty else { return nil }

        var pool = matches
        let idMatched = pool.filter { $0.cgWindowID == preferredWindowID }
        if !idMatched.isEmpty {
            pool = idMatched
        }

        if pool.count == 1 { return pool[0] }

        if let ownerBundleIdentifier, Self.isBrowserBundle(ownerBundleIdentifier) {
            let withControls = pool.filter(\.hasStandardWindowControls)
            if !withControls.isEmpty {
                pool = withControls
            }
        }

        if pool.count == 1 { return pool[0] }

        let containingPoint = pool.filter { candidate in
            let frame = candidate.frame
            return !frame.isNull && !frame.isEmpty && frame.contains(point)
        }
        pool = containingPoint.isEmpty ? pool : containingPoint

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

    private static let browserBundleIdentifiers: Set<String> = WindowAXShellResolver.browserBundleIdentifiers

    private static func isBrowserBundle(_ bundleIdentifier: String) -> Bool {
        WindowAXShellResolver.isBrowserBundle(bundleIdentifier)
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
