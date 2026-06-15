import CoreGraphics

struct LeftHalfCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let halfWidth = frame.width / 2
        let rect = CGRect(x: frame.minX, y: frame.minY, width: halfWidth, height: frame.height)
        return WindowCalculationResult(rect: rect, resultingAction: .leftHalf)
    }
}

struct RightHalfCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let halfWidth = frame.width / 2
        let rect = CGRect(x: frame.midX, y: frame.minY, width: halfWidth, height: frame.height)
        return WindowCalculationResult(rect: rect, resultingAction: .rightHalf)
    }
}

struct TopHalfCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let halfHeight = frame.height / 2
        let rect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: halfHeight)
        return WindowCalculationResult(rect: rect, resultingAction: .topHalf)
    }
}

struct BottomHalfCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let halfHeight = frame.height / 2
        let rect = CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: halfHeight)
        return WindowCalculationResult(rect: rect, resultingAction: .bottomHalf)
    }
}

struct TopLeftCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let rect = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width / 2,
            height: frame.height / 2
        )
        return WindowCalculationResult(rect: rect, resultingAction: .topLeft)
    }
}

struct TopRightCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let rect = CGRect(
            x: frame.midX,
            y: frame.minY,
            width: frame.width / 2,
            height: frame.height / 2
        )
        return WindowCalculationResult(rect: rect, resultingAction: .topRight)
    }
}

struct BottomLeftCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let rect = CGRect(
            x: frame.minX,
            y: frame.midY,
            width: frame.width / 2,
            height: frame.height / 2
        )
        return WindowCalculationResult(rect: rect, resultingAction: .bottomLeft)
    }
}

struct BottomRightCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let rect = CGRect(
            x: frame.midX,
            y: frame.midY,
            width: frame.width / 2,
            height: frame.height / 2
        )
        return WindowCalculationResult(rect: rect, resultingAction: .bottomRight)
    }
}

struct MaximizeCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        WindowCalculationResult(rect: params.visibleFrame, resultingAction: .maximize)
    }
}

struct AlmostMaximizeCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let frame = params.visibleFrame
        let size = CGSize(width: frame.width * 0.9, height: frame.height * 0.9)
        let rect = WindowCalculationGeometry.centeredRect(size: size, in: frame)
        return WindowCalculationResult(rect: rect, resultingAction: .almostMaximize)
    }
}

struct CenterCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let size = params.currentFrame.size
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = WindowCalculationGeometry.centeredRect(size: size, in: params.visibleFrame)
        return WindowCalculationResult(rect: rect, resultingAction: .center)
    }
}

struct TranslateToDisplayCalculation: WindowCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        guard let sourceVisibleFrame = params.sourceVisibleFrame else { return nil }
        let currentFrame = params.currentFrame
        let targetVisibleFrame = params.visibleFrame

        let offsetX = currentFrame.minX - sourceVisibleFrame.minX
        let offsetY = currentFrame.minY - sourceVisibleFrame.minY

        let translated = CGRect(
            x: targetVisibleFrame.minX + offsetX,
            y: targetVisibleFrame.minY + offsetY,
            width: currentFrame.width,
            height: currentFrame.height
        )

        let rect = WindowCalculationGeometry.clamped(translated, to: targetVisibleFrame)
        return WindowCalculationResult(rect: rect, resultingAction: params.action)
    }
}
