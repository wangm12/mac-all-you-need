import Core
import CoreGraphics
import Foundation

public enum WindowCrossDisplayRetry {
  private static let sizeTolerance: CGFloat = 0.5
  private static let originTolerance: CGFloat = 0.5

  public static func needsSizeCorrection(actual: CGRect, proposed: CGRect) -> Bool {
    abs(actual.size.width - proposed.size.width) >= sizeTolerance
      || abs(actual.size.height - proposed.size.height) >= sizeTolerance
  }

  public static func needsFrameCorrection(actual: CGRect, proposed: CGRect) -> Bool {
    needsSizeCorrection(actual: actual, proposed: proposed)
      || abs(actual.origin.x - proposed.origin.x) >= originTolerance
      || abs(actual.origin.y - proposed.origin.y) >= originTolerance
  }

  public static func isCrossDisplayMove(
    action: WindowAction,
    originalFrame: CGRect,
    proposedFrame: CGRect,
    screenDetector: any WindowScreenDetecting
  ) -> Bool {
    switch action {
    case .nextDisplay, .previousDisplay:
      return true
    default:
      break
    }
    guard let source = screenDetector.screen(containing: originalFrame),
          let target = screenDetector.screen(containing: proposedFrame)
    else {
      return false
    }
    return source.id != target.id
  }
}
