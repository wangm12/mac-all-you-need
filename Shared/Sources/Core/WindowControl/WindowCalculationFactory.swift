import CoreGraphics

public enum WindowCalculationFactory: Sendable {
    private static let leftHalf = LeftHalfCalculation()
    private static let rightHalf = RightHalfCalculation()
    private static let topHalf = TopHalfCalculation()
    private static let bottomHalf = BottomHalfCalculation()
    private static let topLeft = TopLeftCalculation()
    private static let topRight = TopRightCalculation()
    private static let bottomLeft = BottomLeftCalculation()
    private static let bottomRight = BottomRightCalculation()
    private static let maximize = MaximizeCalculation()
    private static let almostMaximize = AlmostMaximizeCalculation()
    private static let center = CenterCalculation()
    private static let translateToDisplay = TranslateToDisplayCalculation()

    public static func calculation(for action: WindowAction) -> (any WindowCalculation)? {
        switch action {
        case .leftHalf: leftHalf
        case .rightHalf: rightHalf
        case .topHalf: topHalf
        case .bottomHalf: bottomHalf
        case .topLeft: topLeft
        case .topRight: topRight
        case .bottomLeft: bottomLeft
        case .bottomRight: bottomRight
        case .maximize: maximize
        case .almostMaximize: almostMaximize
        case .center: center
        case .nextDisplay, .previousDisplay: translateToDisplay
        case .restore, .nextSpace, .previousSpace: nil
        }
    }

    public static func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        guard let calculation = calculation(for: params.action) else { return nil }
        return calculation.calculate(params)
    }

    public static func rect(
        for action: WindowAction,
        visibleFrame: CGRect,
        currentSize: CGSize? = nil
    ) -> CGRect? {
        let params = WindowCalculationParameters(
            currentFrame: CGRect(origin: .zero, size: currentSize ?? .zero),
            visibleFrame: visibleFrame,
            action: action
        )
        return calculate(params)?.rect
    }

    public static func rectForMovingDisplay(
        currentFrame: CGRect,
        sourceVisibleFrame: CGRect,
        targetVisibleFrame: CGRect,
        action: WindowAction = .nextDisplay
    ) -> CGRect {
        let params = WindowCalculationParameters(
            currentFrame: currentFrame,
            visibleFrame: targetVisibleFrame,
            sourceVisibleFrame: sourceVisibleFrame,
            action: action
        )
        return calculate(params)?.rect ?? currentFrame
    }
}
