import CoreGraphics
import Foundation

/// Feasibility spike: minimal BSP partition for two-window split (Phase C).
public enum BSPAutoFlowSpike: Sendable {
    public enum Split: Sendable {
        case horizontal
        case vertical
    }

    public static func splitTwoWindows(in visibleFrame: CGRect, orientation: Split = .vertical) -> (CGRect, CGRect) {
        switch orientation {
        case .vertical:
            let half = visibleFrame.width / 2
            let left = CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: half, height: visibleFrame.height)
            let right = CGRect(x: visibleFrame.minX + half, y: visibleFrame.minY, width: half, height: visibleFrame.height)
            return (left, right)
        case .horizontal:
            let half = visibleFrame.height / 2
            let top = CGRect(x: visibleFrame.minX, y: visibleFrame.minY + half, width: visibleFrame.width, height: half)
            let bottom = CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: half)
            return (top, bottom)
        }
    }
}

public enum WindowAutoFlowSpikeFlag {
    public static let userDefaultsKey = "windowAutoFlow.spikeEnabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
}
