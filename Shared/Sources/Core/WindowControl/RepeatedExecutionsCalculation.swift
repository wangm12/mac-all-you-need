import CoreGraphics

/// Shared cycling machinery for future divisional layouts (thirds, fourths, etc.).
/// Not wired to any user action in Phase 3.
public protocol RepeatedExecutionsCalculation: WindowCalculation {
    associatedtype Step: Hashable & Sendable

    var steps: [Step] { get }

    func rect(for step: Step, params: WindowCalculationParameters) -> CGRect?
    func resultingAction(for step: Step) -> WindowAction
}

public extension RepeatedExecutionsCalculation {
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        guard let first = steps.first,
              let rect = rect(for: first, params: params)
        else {
            return nil
        }
        return WindowCalculationResult(rect: rect, resultingAction: resultingAction(for: first))
    }

    func calculate(
        _ params: WindowCalculationParameters,
        lastStep: Step?
    ) -> WindowCalculationResult? {
        let step: Step
        if let lastStep, let index = steps.firstIndex(of: lastStep) {
            let nextIndex = (index + 1) % steps.count
            step = steps[nextIndex]
        } else {
            step = steps[0]
        }
        guard let rect = rect(for: step, params: params) else { return nil }
        return WindowCalculationResult(rect: rect, resultingAction: resultingAction(for: step))
    }
}
