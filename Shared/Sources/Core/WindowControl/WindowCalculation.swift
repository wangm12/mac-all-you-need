import CoreGraphics

public struct WindowCalculationParameters: Sendable {
    public let currentFrame: CGRect
    public let visibleFrame: CGRect
    public let sourceVisibleFrame: CGRect?
    public let action: WindowAction
    public let preserveSize: Bool

    public init(
        currentFrame: CGRect,
        visibleFrame: CGRect,
        sourceVisibleFrame: CGRect? = nil,
        action: WindowAction,
        preserveSize: Bool = false
    ) {
        self.currentFrame = currentFrame
        self.visibleFrame = visibleFrame
        self.sourceVisibleFrame = sourceVisibleFrame
        self.action = action
        self.preserveSize = preserveSize
    }
}

public struct WindowCalculationResult: Sendable {
    public let rect: CGRect
    public let resultingAction: WindowAction

    public init(rect: CGRect, resultingAction: WindowAction) {
        self.rect = rect
        self.resultingAction = resultingAction
    }
}

public protocol WindowCalculation: Sendable {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult?
}
