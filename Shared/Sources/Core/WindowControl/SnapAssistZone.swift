import CoreGraphics
import Foundation

public enum SnapAssistZone: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case center

    public var windowAction: WindowAction {
        switch self {
        case .leftHalf: .leftHalf
        case .rightHalf: .rightHalf
        case .topHalf: .topHalf
        case .bottomHalf: .bottomHalf
        case .maximize: .maximize
        case .center: .center
        }
    }
}

public struct SnapAssistZoneHitTester: Sendable {
    public var insetFraction: CGFloat

    public init(insetFraction: CGFloat = 0.25) {
        self.insetFraction = insetFraction
    }

    public func zone(at point: CGPoint, in visibleFrame: CGRect) -> SnapAssistZone? {
        guard visibleFrame.contains(point) else { return nil }
        let insetX = visibleFrame.width * insetFraction
        let insetY = visibleFrame.height * insetFraction
        let inner = visibleFrame.insetBy(dx: insetX, dy: insetY)

        if inner.contains(point) {
            return .center
        }

        let leftBand = CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: insetX, height: visibleFrame.height)
        let rightBand = CGRect(x: visibleFrame.maxX - insetX, y: visibleFrame.minY, width: insetX, height: visibleFrame.height)
        let topBand = CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: insetY)
        let bottomBand = CGRect(x: visibleFrame.minX, y: visibleFrame.maxY - insetY, width: visibleFrame.width, height: insetY)

        if leftBand.contains(point) { return .leftHalf }
        if rightBand.contains(point) { return .rightHalf }
        if topBand.contains(point) { return .topHalf }
        if bottomBand.contains(point) { return .bottomHalf }

        return nil
    }

    public func previewFrame(for zone: SnapAssistZone, in visibleFrame: CGRect) -> CGRect {
        switch zone {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height)
        case .rightHalf:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: visibleFrame.width / 2, height: visibleFrame.height)
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: visibleFrame.height / 2)
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: visibleFrame.height / 2)
        case .maximize:
            return visibleFrame
        case .center:
            let insetX = visibleFrame.width * insetFraction
            let insetY = visibleFrame.height * insetFraction
            return visibleFrame.insetBy(dx: insetX, dy: insetY)
        }
    }
}
