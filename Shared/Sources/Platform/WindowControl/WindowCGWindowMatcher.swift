import CoreGraphics

/// Matches AX-focused windows to on-screen CGWindowIDs by PID and frame.
public enum WindowCGWindowMatcher {
    public static func windowID(
        forProcessIdentifier pid: pid_t,
        frame: CGRect,
        tolerance: CGFloat = 6
    ) -> CGWindowID? {
        WindowTargetResolver.currentOnScreenWindows().first { info in
            info.processIdentifier == pid
                && info.layer == 0
                && !info.isDesktopElement
                && framesMatch(info.bounds, frame, tolerance: tolerance)
        }?.windowID
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
