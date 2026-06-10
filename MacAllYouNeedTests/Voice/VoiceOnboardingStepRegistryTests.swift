@testable import MacAllYouNeed
import XCTest

/// Frozen registry test: verifies step order and sequential transitions.
final class VoiceOnboardingStepRegistryTests: XCTestCase {
    func testStepCountIsSeven() {
        XCTAssertEqual(VoiceOnboardingStep.orderedCases.count, 7)
    }

    func testFrozenStepTypeNames() {
        let names = VoiceOnboardingStep.orderedCases.map(\.rawValue)
        XCTAssertEqual(names, [
            "welcome",
            "asr",
            "llm",
            "hotkey",
            "languages",
            "tryIt",
            "done"
        ])
    }

    func testEachStepNextIsSuccessor() {
        let ordered = VoiceOnboardingStep.orderedCases
        for i in 0 ..< ordered.count - 1 {
            let current = ordered[i]
            let expected = ordered[i + 1]
            XCTAssertEqual(
                current.next, expected,
                "\(current.rawValue).next should be \(expected.rawValue)"
            )
        }
    }

    func testDoneHasNoNext() {
        XCTAssertNil(VoiceOnboardingStep.done.next)
    }

    func testWelcomeHasNoPrevious() {
        XCTAssertNil(VoiceOnboardingStep.welcome.previous)
    }

    func testEachStepPreviousIsAntecedent() {
        let ordered = VoiceOnboardingStep.orderedCases
        for i in 1 ..< ordered.count {
            let current = ordered[i]
            let expected = ordered[i - 1]
            XCTAssertEqual(
                current.previous, expected,
                "\(current.rawValue).previous should be \(expected.rawValue)"
            )
        }
    }
}
