@testable import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceLiveASRQualityCheckTests: XCTestCase {
    func testLooksSuspicious_lowCharsPerSecond() {
        let captured = CapturedAudio(
            samples: Array(repeating: Float(0.1), count: 480_000),
            sampleRate: 16_000,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 30),
            peakLevel: 0.5
        )
        let result = VoiceTranscriptionResult(
            text: "x",
            language: .mixed,
            modelIdentifier: "qwen3-asr-0.6b"
        )
        XCTAssertTrue(VoiceLiveASRQualityCheck.looksSuspicious(result: result, captured: captured))
    }

    func testLooksSuspicious_acceptsHealthyTranscript() {
        let captured = CapturedAudio(
            samples: Array(repeating: Float(0.1), count: 48_000),
            sampleRate: 16_000,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 3),
            peakLevel: 0.5
        )
        let result = VoiceTranscriptionResult(
            text: "今天天气很好",
            language: .mixed,
            modelIdentifier: "qwen3-asr-0.6b"
        )
        XCTAssertFalse(VoiceLiveASRQualityCheck.looksSuspicious(result: result, captured: captured))
    }
}
