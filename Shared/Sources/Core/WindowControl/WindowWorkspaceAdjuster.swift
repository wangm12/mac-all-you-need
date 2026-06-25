import CoreGraphics

/// Rectangle-style workspace adjustments (edge gaps, future Stage/Todo/notch).
public enum WindowWorkspaceAdjuster {
    /// Insets the visible workspace by a uniform edge gap (Rectangle `GapCalculation` foundation).
    public static func adjustedVisibleFrame(
        _ visibleFrame: CGRect,
        edgeGap: CGFloat = 0
    ) -> CGRect {
        guard edgeGap > 0 else { return visibleFrame }
        let maxInset = min(visibleFrame.width, visibleFrame.height) / 4
        let inset = min(edgeGap, maxInset)
        guard inset > 0 else { return visibleFrame }
        return visibleFrame.insetBy(dx: inset, dy: inset)
    }
}
