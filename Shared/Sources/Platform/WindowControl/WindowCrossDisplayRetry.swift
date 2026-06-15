import Core
import CoreGraphics
import Foundation

public enum WindowCrossDisplayRetry {
  private static let sizeTolerance: CGFloat = 0.5

  public static func needsSizeCorrection(actual: CGRect, proposed: CGRect) -> Bool {
    abs(actual.size.width - proposed.size.width) >= sizeTolerance
      || abs(actual.size.height - proposed.size.height) >= sizeTolerance
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
