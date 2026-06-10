@testable import Core
@testable import MacAllYouNeed
import OSLog
import XCTest

@MainActor
final class VoiceCleanupBudgetTimingTests: XCTestCase {
    func testCleanupPhase_usesCleanupBudgetStartedAt_notOperationStart() async {
        let cleanupBudgetStart = Date()
        let operationStart = cleanupBudgetStart.addingTimeInterval(-1.5)
        var ctx = VoicePipelineContext(
            captured: CapturedAudio(
                samples: Array(repeating: 0.1, count: 1600),
                sampleRate: 16_000,
                startedAt: operationStart,
                endedAt: cleanupBudgetStart,
                peakLevel: 0.2
            ),
            presetASRResult: VoiceTranscriptionResult(
                text: "hello",
                language: .english,
                modelIdentifier: "stub"
            ),
            appBundleID: nil,
            generation: 1,
            operationStartedAt: operationStart
        )
        ctx.asrResult = ctx.presetASRResult
        ctx.cleanupBudgetStartedAt = cleanupBudgetStart

        var elapsedPassedToFactory: TimeInterval?
        let phase = CleanupPhase(
            makePipeline: { elapsed in
                elapsedPassedToFactory = elapsed
                return VoiceCleanupPipeline()
            },
            personalization: .init(
                dictionaryEntries: [],
                appContext: nil,
                globalContext: nil,
                recentExamples: []
            ),
            observer: nil,
            log: Logger(subsystem: "test", category: "voice")
        )

        await phase.run(&ctx)

        XCTAssertNotNil(elapsedPassedToFactory)
        XCTAssertLessThan(elapsedPassedToFactory ?? 999, 0.2)
    }
}
